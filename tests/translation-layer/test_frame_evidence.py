#!/usr/bin/env python3
"""Real Apple PNG encoder and streaming ZIP exporter, cross-read by Python."""
import json,subprocess,sys,tempfile,unittest,zipfile,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
@unittest.skipUnless(sys.platform=='darwin','Apple CoreGraphics/ImageIO required; IPA CI runs this check')
class FrameEvidenceTests(unittest.TestCase):
 def test_lossless_bgra_export_zip_integrity_bounds_and_partial_capture(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);capture=p/'capture';frames=capture/'frames';frames.mkdir(parents=True)
   (capture/'host-session.json').write_text('{"host_session_id":"test-capture"}')
   files=[]
   for i,stage in enumerate(['previous','current','generated','following-real','forward','backward']):
    field=i>=4;name='pair-01-'+stage+('.f16'if field else'.bgra')
    raw=(bytes([3+i,10+i,100+i,255])*2+bytes(248))*2 if not field else bytes([i])*512
    (frames/name).write_bytes(raw)
    files.append(dict(stage=stage,file=name,width=2,height=2,row_bytes=256,bytes=len(raw),format='RGBA16Float'if field else'BGRA8Unorm'))
   manifest=dict(schema=1,state='complete',files=files)
   (frames/'pair-01.json').write_text(json.dumps(manifest))
   log=p/'husk.log';log.write_bytes(b'IDENTITY: build169\n'+b'A'*(2*1024*1024)+b'END OF LOG\n')
   before=hashlib.sha256(log.read_bytes()).hexdigest()
   (p/'main.swift').write_text(r'''
import Foundation
import CoreGraphics
import ImageIO
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let capture=root.appendingPathComponent("capture"),output=root.appendingPathComponent("evidence.zip")
try FrameEvidenceFiles.bundle(capture:capture,logs:[root.appendingPathComponent("husk.log")],context:Data("{}".utf8),output:output)
let png=root.appendingPathComponent("check.png")
let raw=capture.appendingPathComponent("frames/pair-01-previous.bgra")
let meta:[String:Any]=["format":"BGRA8Unorm","width":2,"height":2,"row_bytes":256]
try FrameEvidenceFiles.png(raw:raw,metadata:meta,to:png)
let source=CGImageSourceCreateWithURL(png as CFURL,nil)!,image=CGImageSourceCreateImageAtIndex(source,0,nil)!
precondition(image.width==2 && image.height==2)
var pixels=[UInt8](repeating:0,count:16)
pixels.withUnsafeMutableBytes { bytes in
 let ctx=CGContext(data:bytes.baseAddress,width:2,height:2,bitsPerComponent:8,bytesPerRow:8,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 ctx.draw(image,in:CGRect(x:0,y:0,width:2,height:2))
}
for i in stride(from:0,to:16,by:4){precondition(pixels[i]==100 && pixels[i+1]==10 && pixels[i+2]==3 && pixels[i+3]==255)}
func rejected(_ name:String,_ fn:()throws->Void){do{try fn();fatalError("accepted invalid \(name)")}catch{precondition(!FileManager.default.fileExists(atPath:root.appendingPathComponent(name+".zip.partial").path))}}
let entry=DiagnosticArchive.Entry(name:"../outside",url:raw)
rejected("unsafe"){try DiagnosticArchive.write([entry],to:root.appendingPathComponent("unsafe.zip"))}
rejected("limit"){try DiagnosticArchive.write([.init(name:"safe",url:raw)],to:root.appendingPathComponent("limit.zip"),limit:30)}
rejected("duplicate"){try DiagnosticArchive.write([.init(name:"same",url:raw),.init(name:"same",url:raw)],to:root.appendingPathComponent("duplicate.zip"))}
let symlink=root.appendingPathComponent("link")
try FileManager.default.createSymbolicLink(at:symlink,withDestinationURL:raw)
rejected("symlink"){try DiagnosticArchive.write([.init(name:"safe",url:symlink)],to:root.appendingPathComponent("symlink.zip"))}
var bad=meta;bad["row_bytes"]=8
rejected("badrow"){try FrameEvidenceFiles.png(raw:raw,metadata:bad,to:root.appendingPathComponent("bad.png"))}
// A metadata-only failed capture is exportable and explicitly incomplete.
let partial=root.appendingPathComponent("partial/frames");try FileManager.default.createDirectory(at:partial,withIntermediateDirectories:true)
try Data("{\"state\":\"incomplete\",\"error\":\"cancelled\",\"files\":[]}".utf8).write(to:partial.appendingPathComponent("pair-01.json"))
try FrameEvidenceFiles.bundle(capture:partial.deletingLastPathComponent(),logs:[],context:Data("{}".utf8),output:root.appendingPathComponent("partial.zip"))
print("PASS: real Apple BGRA→RGB PNG preserves channels/full pixels; ZIP bounds, symlinks, duplicate entries, incomplete capture")
''')
   binary=p/'probe';subprocess.run(['swiftc',str(ROOT/'src/app/Husk/DiagnosticArchive.swift'),str(ROOT/'src/app/Husk/FrameEvidenceFiles.swift'),str(p/'main.swift'),'-o',str(binary)],check=True)
   subprocess.run([str(binary),str(p)],check=True)
   with zipfile.ZipFile(p/'evidence.zip')as z:
    self.assertIsNone(z.testzip());index=json.loads(z.read('bundle-index.json'));self.assertEqual(index['complete_pairs'],1)
    self.assertEqual(len([n for n in z.namelist()if n.endswith('.png')]),4)
    self.assertEqual(z.read('capture/pair-01-forward.f16'),bytes([4])*512)
    self.assertIn(b'IDENTITY: build169',z.read('logs/husk.log'));self.assertTrue(z.read('logs/husk.log').endswith(b'END OF LOG\n'))
    self.assertEqual(len(index['omissions']),1)
    for entry in index['entries']:
     if 'file'in entry:self.assertEqual(hashlib.sha256(z.read(entry['file'])).hexdigest(),entry['sha256'])
   with zipfile.ZipFile(p/'partial.zip')as z:self.assertEqual(json.loads(z.read('bundle-index.json'))['complete_pairs'],0)
   self.assertEqual(hashlib.sha256(log.read_bytes()).hexdigest(),before)
if __name__=='__main__':unittest.main()
