// TypeMate listening overlay for X11 — matches the Windows overlay:
// a rounded dark pill near the bottom centre with a label and an animated
// waveform. Borderless, always-on-top, and override_redirect so it never
// steals focus from the field being typed into.
//
// The app drives it over stdin with single-word lines: "listening",
// "transcribing", or "hide". EOF exits.
//
// Build: gcc typemate_overlay.c -o typemate-overlay -lX11 -lXext -lm
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/extensions/shape.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/select.h>
#include <sys/time.h>

// Geometry and colours mirror windows/runner/type_mate_overlay.cpp.
enum {
  kWidth = 210,
  kHeight = 58,
  // Lifted well clear of the panel/taskbar (measured from the full screen
  // height, so this needs more than the Windows work-area margin).
  kMarginBottom = 90,
  kBarCount = 7,
  kBarWidth = 5,
  kBarGap = 6,
  kBarMinH = 5,
  kBarMaxH = 18,
  kBarCenterY = 42,
  kTickMs = 70,
};

static unsigned long alloc_color(Display *d, int screen, const char *hex) {
  XColor c;
  Colormap cmap = DefaultColormap(d, screen);
  XParseColor(d, cmap, hex, &c);
  XAllocColor(d, cmap, &c);
  return c.pixel;
}

// Clip the window to a rounded-pill shape via the SHAPE extension, matching
// the Windows CreateRoundRectRgn(radius 58).
static void apply_pill_shape(Display *d, Window w) {
  int r = kHeight / 2; // fully rounded ends
  Pixmap mask = XCreatePixmap(d, w, kWidth, kHeight, 1);
  GC mgc = XCreateGC(d, mask, 0, NULL);
  XSetForeground(d, mgc, 0);
  XFillRectangle(d, mask, mgc, 0, 0, kWidth, kHeight);
  XSetForeground(d, mgc, 1);
  // Body + rounded corners.
  XFillRectangle(d, mask, mgc, r, 0, kWidth - 2 * r, kHeight);
  XFillRectangle(d, mask, mgc, 0, r, kWidth, kHeight - 2 * r);
  XFillArc(d, mask, mgc, 0, 0, 2 * r, 2 * r, 0, 360 * 64);
  XFillArc(d, mask, mgc, kWidth - 2 * r, 0, 2 * r, 2 * r, 0, 360 * 64);
  XFillArc(d, mask, mgc, 0, kHeight - 2 * r, 2 * r, 2 * r, 0, 360 * 64);
  XFillArc(d, mask, mgc, kWidth - 2 * r, kHeight - 2 * r, 2 * r, 2 * r, 0,
           360 * 64);
  XShapeCombineMask(d, w, ShapeBounding, 0, 0, mask, ShapeSet);
  XFreeGC(d, mgc);
  XFreePixmap(d, mask);
}

int main(void) {
  Display *d = XOpenDisplay(NULL);
  if (!d) return 1;
  int screen = DefaultScreen(d);
  Window root = RootWindow(d, screen);
  int sw = DisplayWidth(d, screen);
  int sh = DisplayHeight(d, screen);
  int x = (sw - kWidth) / 2;
  int y = sh - kHeight - kMarginBottom;

  unsigned long bg = alloc_color(d, screen, "#1f2230");
  unsigned long white = alloc_color(d, screen, "#ffffff");
  unsigned long accent = alloc_color(d, screen, "#7a8bff");

  XSetWindowAttributes attrs;
  attrs.override_redirect = True; // bypass the WM: no focus, always on top
  attrs.background_pixel = bg;
  attrs.event_mask = ExposureMask;
  Window win = XCreateWindow(d, root, x, y, kWidth, kHeight, 0, CopyFromParent,
                             InputOutput, CopyFromParent,
                             CWOverrideRedirect | CWBackPixel | CWEventMask,
                             &attrs);

  Atom wmState = XInternAtom(d, "_NET_WM_STATE", False);
  Atom above = XInternAtom(d, "_NET_WM_STATE_ABOVE", False);
  XChangeProperty(d, win, wmState, XA_ATOM, 32, PropModeReplace,
                  (unsigned char *)&above, 1);

  int shape_evbase, shape_errbase;
  if (XShapeQueryExtension(d, &shape_evbase, &shape_errbase)) {
    apply_pill_shape(d, win);
  }

  // Double buffer to keep the waveform flicker-free.
  Pixmap buffer = XCreatePixmap(d, win, kWidth, kHeight,
                                DefaultDepth(d, screen));
  GC gc = XCreateGC(d, win, 0, NULL);
  // XCopyArea would otherwise send a NoExpose event per blit; that event
  // traffic must not wake (or worse, pace) the animation loop.
  XSetGraphicsExposures(d, gc, False);
  XFontStruct *font = XLoadQueryFont(d, "-*-helvetica-bold-r-*-*-13-*");
  if (!font) font = XLoadQueryFont(d, "-*-*-bold-r-*-*-13-*");
  if (!font) font = XLoadQueryFont(d, "fixed");
  if (font) XSetFont(d, gc, font->fid);

  const char *label = "TypeMate is listening...";
  // Map immediately: the app spawns one overlay per dictation, so being
  // spawned means "show now". stdin only updates the state after that,
  // which sidesteps any buffering on the parent's write of the first
  // command.
  XMapRaised(d, win);
  int visible = 1;
  long tick = 0;

  int xfd = ConnectionNumber(d);
  char buf[128];

  // The animation is paced by wall time, like the Windows WM_TIMER: one
  // frame per kTickMs, regardless of how often X events wake the loop.
  struct timespec next;
  clock_gettime(CLOCK_MONOTONIC, &next);
  int dirty = 1;

  while (1) {
    while (XPending(d)) {
      XEvent ev;
      XNextEvent(d, &ev);
      if (ev.type == Expose) dirty = 1;
    }

    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    long remain_us = (next.tv_sec - now.tv_sec) * 1000000L +
                     (next.tv_nsec - now.tv_nsec) / 1000L;
    if (visible && remain_us <= 0) {
      tick++;
      dirty = 1;
      // Re-anchor rather than burst-catch-up if the process was paused.
      if (remain_us < -kTickMs * 1000L) next = now;
      next.tv_nsec += kTickMs * 1000000L;
      while (next.tv_nsec >= 1000000000L) {
        next.tv_nsec -= 1000000000L;
        next.tv_sec++;
      }
      remain_us = kTickMs * 1000L;
    }

    if (visible && dirty) {
      dirty = 0;
      // Paint into the back buffer.
      XSetForeground(d, gc, bg);
      XFillRectangle(d, buffer, gc, 0, 0, kWidth, kHeight);

      XSetForeground(d, gc, white);
      int tw = font ? XTextWidth(font, label, strlen(label)) : 0;
      int tx = (kWidth - tw) / 2;
      XDrawString(d, buffer, gc, tx, 22, label, strlen(label));

      XSetForeground(d, gc, accent);
      int total = kBarCount * kBarWidth + (kBarCount - 1) * kBarGap;
      int startx = (kWidth - total) / 2;
      for (int i = 0; i < kBarCount; i++) {
        // Same wave as the Windows overlay: 0.55 rad per 70 ms frame; the
        // wall-clock deadline above owns the cadence.
        double phase = (tick + i * 2) * 0.55;
        int h = kBarMinH +
                (int)(((sin(phase) + 1.0) / 2.0) * (kBarMaxH - kBarMinH));
        int bx = startx + i * (kBarWidth + kBarGap);
        int by = kBarCenterY - h / 2;
        XFillRectangle(d, buffer, gc, bx, by, kBarWidth, h);
      }
      XCopyArea(d, buffer, win, gc, 0, 0, kWidth, kHeight, 0, 0);
      XFlush(d);
    }

    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(xfd, &fds);
    FD_SET(STDIN_FILENO, &fds);
    int maxfd = xfd > STDIN_FILENO ? xfd : STDIN_FILENO;
    struct timeval tv;
    tv.tv_sec = remain_us / 1000000L;
    tv.tv_usec = remain_us % 1000000L;
    // Sleep until the next frame deadline or an fd wakes us; the deadline
    // check above owns the animation cadence either way.
    int r = select(maxfd + 1, &fds, NULL, NULL, visible ? &tv : NULL);

    if (r > 0 && FD_ISSET(STDIN_FILENO, &fds)) {
      ssize_t n = read(STDIN_FILENO, buf, sizeof(buf) - 1);
      if (n <= 0) break; // EOF -> exit
      buf[n] = '\0';
      char *cmd = strtok(buf, "\r\n");
      char *last = NULL;
      while (cmd) { last = cmd; cmd = strtok(NULL, "\r\n"); }
      if (!last) continue;
      if (strcmp(last, "hide") == 0) {
        break; // the app dismisses by asking to hide or by closing stdin
      }
      label = strcmp(last, "transcribing") == 0 ? "Transcribing locally..."
                                                : "TypeMate is listening...";
      dirty = 1;
      if (!visible) { XMapRaised(d, win); visible = 1; }
      XRaiseWindow(d, win);
    }
  }
  XCloseDisplay(d);
  return 0;
}
