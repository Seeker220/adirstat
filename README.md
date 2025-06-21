# ADirStat

## Overview

**ADirStat** is a root-required Android app that visualizes storage usage with a detailed TreeMap. It uses inode tracking to detect and skip duplicate files and directories for accurate storage analysis.

---

## Features

* 📊 **TreeMap Visualization:** Clean storage map using `syncfusion_flutter_treemap` on Flutter's Canvas.
* 🔍 **Duplicate Detection:** Tracks inodes and storage sizes to skip duplicates, including symlinks.
* 🚀 **Efficient Scanning:** Uses BFS traversal starting from `/` with `ls -lai -1` and `du` for size calculation.
* 🔒 **Root Access Required:** Needs superuser (su) permissions to access system paths.

---

## Notes

* Symlinks are treated as files to prevent loops.
* Duplicate directories (by inode) are automatically excluded.

---

## Changelog

### v1.1.0

* 🎨 Added true random colorization for better visual distinction.
* 📂 Added display of percentage and storage used in the explorer view.
* 📁 Added **Open in File Manager** option on long press in the explorer menu.
