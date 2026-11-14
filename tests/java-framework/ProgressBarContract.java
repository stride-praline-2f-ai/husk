import android.content.Context;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.widget.ProgressBar;

/** Runs the real ProgressBar with host facades for the native window/resource boundary. */
public final class ProgressBarContract {
    private static int checks;
    private static void check(boolean ok, String message) {
        checks++;
        if (!ok) throw new AssertionError(message);
    }
    static final class TypedDrawable extends ColorDrawable {}
    static final class MaterialLike extends ProgressBar {
        MaterialLike(Context c) { super(c); }
        @Override public TypedDrawable getIndeterminateDrawable() {
            return (TypedDrawable) super.getIndeterminateDrawable();
        }
        @Override public void invalidate() {
            super.invalidate();
            Drawable d = getIndeterminateDrawable();
            if (d != null) d.invalidateSelf();
        }
    }
    static final class ConstructionGuard extends ProgressBar {
        private boolean ready;
        ConstructionGuard(Context c) { super(c); ready = true; }
        @Override public void invalidate() {
            if (!ready) throw new AssertionError("subclass invalidated before its constructor");
            super.invalidate();
        }
    }
    public static void main(String[] args) {
        Context c = new Context();
        MaterialLike material = new MaterialLike(c);
        ProgressBar bare = new ProgressBar(c);
        check(bare.getIndeterminateDrawable() == null, "missing drawable stays null");
        check(bare.getIndeterminateDrawable() == null, "getter never manufactures a placeholder");
        check(material.getIndeterminateDrawable() == null, "covariant getter safe during construction");
        TypedDrawable typed = new TypedDrawable();
        material.setIndeterminateDrawable(typed);
        check(material.getIndeterminateDrawable() == typed, "typed drawable identity preserved");
        material.setIndeterminateDrawable(null);
        check(material.getIndeterminateDrawable() == null, "clear does not restore a stale drawable");
        Context themed = new Context();
        ColorDrawable themeDrawable = new ColorDrawable(0xff123456);
        themed.indeterminate = themeDrawable;
        ProgressBar themeBar = new ProgressBar(themed);
        check(themeBar.getIndeterminateDrawable() == themeDrawable, "real themed drawable retained");
        themeBar.setIndeterminateDrawable(null);
        check(themeBar.getIndeterminateDrawable() == null, "clearing a theme drawable stays null");
        Context withProgress = new Context();
        withProgress.progress = new ColorDrawable();
        ConstructionGuard guarded = new ConstructionGuard(withProgress);
        check(guarded.getProgressDrawable() == withProgress.progress, "constructor retains progress drawable");
        guarded.setIndeterminate(false);
        int before = guarded.invalidations;
        guarded.setProgress(50);
        check(guarded.invalidations > before, "post-construction progress still invalidates");
        check(guarded.getProgressDrawable().getLevel() == 5000, "progress drawable level refreshed");
        System.out.println("ProgressBar contract: " + checks + " checks passed");
    }
}
