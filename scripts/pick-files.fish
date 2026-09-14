#!/usr/bin/env fish

# Portal file picker. Args: MODE [OUTFILE DONEFILE]
# MODE: files | folder | images | paste
# Writes chosen paths to OUTFILE (or stdout) and DONEFILE with the exit code.

set -gx PATH /usr/bin /usr/local/bin $HOME/.local/bin $PATH
set -e GDK_BACKEND
set -e QT_QPA_PLATFORM

set -l mode $argv[1]
if test -z "$mode"
  set mode files
end

set -l out $argv[2]
set -l done $argv[3]
set -l script_dir (status dirname)
set -l py $script_dir/pick-files.py

function write_done
  if test -n "$done"
    echo $argv[1] > "$done"
  end
end

if test "$mode" = paste
  set -l dest $argv[2]
  if test -z "$dest"
    echo "missing paste destination" >&2
    write_done 2
    exit 2
  end
  if not command -q wl-paste
    echo "wl-paste not found" >&2
    write_done 127
    exit 127
  end
  wl-paste --no-newline --type image/png > "$dest"
  set -l st $status
  if test $st -ne 0 -o ! -s "$dest"
    echo "No image on the clipboard" >&2
    rm -f "$dest"
    write_done 1
    exit 1
  end
  echo "$dest"
  write_done 0
  exit 0
end

set -l tmp
if test -n "$out"
  mkdir -p (dirname "$out")
  rm -f "$out" "$done"
  set tmp $out
else
  set tmp /dev/stdout
end

set -l st 127

if test -f "$py"; and command -q python3
  python3 "$py" $mode $tmp $done 2>/tmp/alfred-pick.err
  set st $status
  if test -s "$done"
    set st (string trim < "$done")
  end
end

if test $st -eq 127
  if command -q zenity
    switch $mode
      case folder
        zenity --file-selection --directory --title="Add folder to Alfred" > $tmp
      case images
        zenity --file-selection --multiple --separator=\n --title="Add images to Alfred" --file-filter="Images | *.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg" > $tmp
      case '*'
        zenity --file-selection --multiple --separator=\n --title="Add files to Alfred" > $tmp
    end
    set st $status
  else if command -q kdialog
    switch $mode
      case folder
        kdialog --title "Add folder to Alfred" --getexistingdirectory "$HOME" > $tmp
      case images
        kdialog --title "Add images to Alfred" --getopenfilename "$HOME" "Images (*.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg)" --multiple > $tmp
      case '*'
        kdialog --title "Add files to Alfred" --getopenfilename "$HOME" --multiple > $tmp
    end
    set st $status
  end
end

write_done $st
exit $st
