#!/usr/bin/env python3
"""Exercise actual widget bytecode; only native platform boundaries use host facades."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FACADES = {
    'android/util/DisplayMetrics.java': '''package android.util;
public class DisplayMetrics { public float density = 1; }''',
    'android/os/SystemClock.java': '''package android.os;
public class SystemClock { public static long uptimeMillis() { return 1; } }''',
    'android/content/res/Resources.java': '''package android.content.res;
public class Resources {
 public android.util.DisplayMetrics getDisplayMetrics() { return new android.util.DisplayMetrics(); }
 public class Theme { public boolean resolveAttribute(int id, android.util.TypedValue v, boolean refs) { return false; } }
}''',
    'android/content/Context.java': '''package android.content;
public class Context {
 public android.graphics.drawable.Drawable progress, indeterminate;
 public android.content.res.Resources getResources() { return new android.content.res.Resources(); }
 public android.content.res.Resources.Theme getTheme() { return getResources().new Theme(); }
 public int getColor(int id) { return 0; }
 public android.content.res.TypedArray obtainStyledAttributes(android.util.AttributeSet a, int[] ids, int s, int r) {
  return new android.content.res.TypedArray(this);
 }
}''',
    'android/content/res/TypedArray.java': '''package android.content.res;
public class TypedArray {
 private final android.content.Context c;
 public TypedArray(android.content.Context c) { this.c = c; }
 public android.graphics.drawable.Drawable getDrawable(int i) {
  return i == husk.S.ProgressBar_progressDrawable ? c.progress : c.indeterminate;
 }
 public int getDimensionPixelSize(int i, int d) { return d; }
 public int getInt(int i, int d) { return d; }
 public boolean getBoolean(int i, boolean d) { return d; }
 public boolean hasValue(int i) { return false; }
 public ColorStateList getColorStateList(int i) { return null; }
 public void recycle() {}
}''',
    'android/view/View.java': '''package android.view;
import android.graphics.drawable.Drawable;
public class View implements Drawable.Callback {
 public static final int VISIBLE = 0;
 public int invalidations;
 private final android.content.Context c;
 public View(android.content.Context c, android.util.AttributeSet a, int s, int r) { this.c = c; }
 public android.content.Context getContext() { return c; }
 public android.content.res.Resources getResources() { return c.getResources(); }
 public void invalidate() { invalidations++; }
 public void invalidate(int l, int t, int r, int b) { invalidations++; }
 public void requestLayout() {}
 public void postInvalidateOnAnimation() {}
 public int getVisibility() { return VISIBLE; }
 public int getWindowVisibility() { return VISIBLE; }
 public int getWidth() { return 100; }
 public int getHeight() { return 10; }
 public int getPaddingLeft() { return 0; } public int getPaddingRight() { return 0; }
 public int getPaddingTop() { return 0; } public int getPaddingBottom() { return 0; }
 public int[] getDrawableState() { return new int[0]; }
 protected void onAttachedToWindow() {} protected void onDetachedFromWindow() {}
 protected void onVisibilityChanged(View v, int vis) {}
 protected boolean verifyDrawable(Drawable d) { return false; }
 public void invalidateDrawable(Drawable d) {}
 public void scheduleDrawable(Drawable d, Runnable r, long when) {}
 public void unscheduleDrawable(Drawable d, Runnable r) {}
 protected void drawableStateChanged() {}
 protected void onSizeChanged(int w, int h, int ow, int oh) {}
 protected void onDraw(android.graphics.Canvas c) {}
 protected void onMeasure(int w, int h) {}
 public static int resolveSizeAndState(int w, int spec, int state) { return w; }
 protected void setMeasuredDimension(int w, int h) {}
 public CharSequence getAccessibilityClassName() { return "View"; }
}''',
}

def run(classes, source=None):
    jdk = Path(os.environ['HUSK_JDK'])
    with tempfile.TemporaryDirectory() as d:
        base = Path(d)
        sources = []
        for name, content in FACADES.items():
            path = base / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
            sources.append(str(path))
        if source is not None:
            widget = base / 'android/widget/ProgressBar.java'
            widget.parent.mkdir(parents=True)
            widget.write_text(source)
            sources.append(str(widget))
        out = base / 'classes'
        subprocess.run([str(jdk / 'bin/javac'), '--release', '8', '-cp', classes, '-d', str(out),
                        *sources, str(ROOT / 'tests/java-framework/ProgressBarContract.java')], check=True)
        return subprocess.run([str(jdk / 'bin/java'), '-cp', str(out) + os.pathsep + classes,
                               'ProgressBarContract'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

if __name__ == '__main__':
    result = run(sys.argv[1])
    print(result.stdout, end='')
    raise SystemExit(result.returncode)
