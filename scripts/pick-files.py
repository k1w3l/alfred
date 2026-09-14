#!/usr/bin/env python3
"""Pick files via xdg-desktop-portal (GTK fallback). Writes OUT then DONE and exits."""

from __future__ import annotations

import os
import sys
from urllib.parse import unquote, urlparse

os.environ.pop("GDK_BACKEND", None)
os.environ.pop("QT_QPA_PLATFORM", None)


def uri_to_path(uri: str) -> str:
    value = str(uri or "").strip()
    if value.startswith("file:"):
        return unquote(urlparse(value).path)
    if value.startswith("/"):
        return value
    return ""


def collect_paths(filenames, uris) -> list[str]:
    paths: list[str] = []
    seen: set[str] = set()
    for item in list(filenames or []) + [uri_to_path(u) for u in list(uris or [])]:
        path = str(item or "").strip()
        if path == "" or path in seen:
            continue
        seen.add(path)
        paths.append(path)
    return paths


def commit(out_path: str, done_path: str, code: int, paths: list[str]) -> None:
    payload = "".join(p + "\n" for p in paths if p)
    if out_path:
        directory = os.path.dirname(out_path)
        if directory:
            os.makedirs(directory, exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
    elif payload:
        sys.stdout.write(payload)
        sys.stdout.flush()
    if done_path:
        directory = os.path.dirname(done_path)
        if directory:
            os.makedirs(directory, exist_ok=True)
        tmp = done_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as handle:
            handle.write(str(int(code)) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, done_path)
    os._exit(int(code))


def dialog_title(mode: str) -> str:
    if mode == "folder":
        return "Add folders as context"
    if mode == "images":
        return "Add images as context"
    return "Add files as context"


def pick_portal(mode: str, out_path: str, done_path: str) -> bool:
    try:
        import gi

        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
    except Exception:
        return False

    loop = GLib.MainLoop()
    token = "alfred%d" % os.getpid()

    def on_response(_conn, _sender, object_path, _iface, _signal, parameters):
        path = str(object_path or "")
        if token not in path and "request" not in path:
            return
        response, results = parameters.unpack()
        data = results if isinstance(results, dict) else {}
        uris = list(data.get("uris") or [])
        if int(response) == 0:
            paths = collect_paths([], uris)
            commit(out_path, done_path, 0 if paths else 1, paths)
        commit(out_path, done_path, 1, [])

    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        bus.signal_subscribe(
            "org.freedesktop.portal.Desktop",
            "org.freedesktop.portal.Request",
            "Response",
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            on_response,
        )
        options = {
            "handle_token": GLib.Variant("s", token),
            "multiple": GLib.Variant("b", mode != "folder"),
            "directory": GLib.Variant("b", mode == "folder"),
            "modal": GLib.Variant("b", False),
        }
        if mode == "images":
            options["filters"] = GLib.Variant(
                "a(sa(us))",
                [
                    (
                        "Images",
                        [
                            (0, "*.png"),
                            (0, "*.jpg"),
                            (0, "*.jpeg"),
                            (0, "*.gif"),
                            (0, "*.webp"),
                            (0, "*.bmp"),
                            (0, "*.svg"),
                        ],
                    )
                ],
            )
        proxy = Gio.DBusProxy.new_sync(
            bus,
            Gio.DBusProxyFlags.NONE,
            None,
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.FileChooser",
            None,
        )
        proxy.call_sync(
            "OpenFile",
            GLib.Variant("(ssa{sv})", ("", dialog_title(mode), options)),
            Gio.DBusCallFlags.NONE,
            -1,
            None,
        )
        GLib.timeout_add_seconds(300, loop.quit)
        loop.run()
    except Exception as exc:
        sys.stderr.write("alfred portal: %s\n" % exc)
        return False
    commit(out_path, done_path, 1, [])
    return True


def pick_gtk(mode: str, out_path: str, done_path: str) -> bool:
    try:
        import gi

        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk
    except Exception:
        return False

    Gtk.init([])
    action = Gtk.FileChooserAction.SELECT_FOLDER if mode == "folder" else Gtk.FileChooserAction.OPEN
    dialog = Gtk.FileChooserNative.new(dialog_title(mode), None, action, "_Open", "_Cancel")
    home = os.path.expanduser("~")
    if os.path.isdir(home):
        dialog.set_current_folder(home)
    if mode != "folder":
        dialog.set_select_multiple(True)
    if mode == "images":
        filt = Gtk.FileFilter()
        filt.set_name("Images")
        for pattern in ("*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.bmp", "*.svg"):
            filt.add_pattern(pattern)
        dialog.add_filter(filt)

    response = dialog.run()
    if response != Gtk.ResponseType.ACCEPT:
        commit(out_path, done_path, 1, [])

    filenames = []
    uris = []
    if mode == "folder":
        name = dialog.get_filename()
        if name:
            filenames.append(name)
        if hasattr(dialog, "get_uri"):
            uri = dialog.get_uri()
            if uri:
                uris.append(uri)
    else:
        filenames = list(dialog.get_filenames() or [])
        if hasattr(dialog, "get_uris"):
            uris = list(dialog.get_uris() or [])
    paths = collect_paths(filenames, uris)
    commit(out_path, done_path, 0 if paths else 1, paths)
    return True


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "files"
    out_path = sys.argv[2] if len(sys.argv) > 2 else ""
    done_path = sys.argv[3] if len(sys.argv) > 3 else ""
    pick_portal(mode, out_path, done_path)
    pick_gtk(mode, out_path, done_path)
    commit(out_path, done_path, 127, [])
