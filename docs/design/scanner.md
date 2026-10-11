# Scanner Design Review (M1-A)

## 1. Data Structures
To handle 10M+ nodes while keeping memory under 150 bytes per node (F2.8, F10), we must avoid Swift `class` instances (which add reference counting and heap allocation overhead).

**Arena Layout:**
We will use an append-only `ContiguousArray<Node>` inside a `TreeStore`. 
```swift
struct Node {
    let id: UInt32                // 4 bytes
    let parent: UInt32            // 4 bytes
    let nameOffset: UInt32        // 4 bytes (Index into a shared [UInt8] string buffer)
    let nameLength: UInt16        // 2 bytes
    let kind: UInt8               // 1 byte (file, dir, package, symlink, etc.)
    let flags: UInt8              // 1 byte (unreadable, hardLinkDeduped)
    var allocatedBytes: UInt64    // 8 bytes
    var logicalBytes: UInt64      // 8 bytes
    var itemCount: UInt32         // 4 bytes
    var childrenStart: UInt32     // 4 bytes (Index into a sibling/child array)
    var childrenCount: UInt32     // 4 bytes
} // Total: ~44 bytes per node
```
**Memory Estimate:** 44 bytes * 10 million nodes = **~440 MB** for the array, plus ~200-300 MB for the raw string byte buffer. This sits comfortably below the 1.5 GB limit (150 bytes * 10M).

## 2. Concurrency Model
**Work Stealing & Threading (F2.1, F2.5):**
- A `TaskGroup` bounded to `ProcessInfo.processInfo.activeProcessorCount`.
- We avoid recursive actor hops. Instead, a local `DirectoryWorker` scans a directory and its immediate files synchronously.
- If it encounters a subdirectory, it spawns a new task in the group (if under concurrency limits) or adds it to a local queue.
- **Contention-Free Rollup:** Tasks return detached, local subtree results (`[Node]`) rather than mutating a shared global tree. A single coordinator loop awaits task results and stitches them into the master `TreeStore` array, rolling up `allocatedBytes` to parents.
- **Partial Snapshots:** The coordinator emits a lightweight `ScanEvent` every 100ms. Since the `TreeStore` is append-only, partial snapshots are just the current `count` of the array.

## 3. macOS Specifics (F2.2, F2.3, F3.2, F10)
- **Filesystem API:** `getattrlistbulk` will be used instead of `readdir` to fetch names and stats (size, inodes) in a single syscall block.
- **Sizes:** We prioritize `ATTR_FILE_ALLOCSIZE`. If missing, we calculate `blocks * 512`. This properly handles APFS sparse files.
- **APFS Clones:** Identical files (clones) may cause total allocated size to fall short of `volume_used_capacity`. This discrepancy is exposed safely as "Hidden space" (F3.2), avoiding negative size crashes.
- **Firmlinks & Data Volume:** We explicitly prevent crossing volume boundaries (via device ID checking). Scanning `/System/Volumes/Data` directly prevents double-counting firmlinks.
- **Packages:** We check the `kMDItemContentTypeTree` or standard `.app`/`.bundle` extensions to flag folders as opaque packages (F2.4).

## 4. Failure Modes (F2.7, F10)
- **Permission Denied (chmod 000):** `getattrlistbulk` returns `EACCES`. The node is stored with `kind = dir`, `flags = unreadable`, and `allocatedBytes = 0`. The skipped counter increments.
- **Vanishing Files:** Handled gracefully. If `lstat` or `getattrlistbulk` fails with `ENOENT` mid-scan, the item is silently ignored.
- **Network Volume Stalls:** `TaskGroup` operations will be wrapped in `withTaskCancellationHandler`. If a network volume hangs, the user clicking "Stop" cancels the tasks, and the coordinator preserves the tree scanned so far.

## 5. Test Plan
- **Synthetic 1M-File Tree:** A Swift script using low-level POSIX `mkdir` and `open(..., O_CREAT)` to rapidly generate 1,000 directories, each with 1,000 empty files. 
- **Validation:** Compare the scanner's output against `du -sk <path>` (kilobytes) and `diskutil info`.
- **Edge-case Fixtures:** A temp folder containing symlink loops, a zero-permission folder, an emoji-named file (🍕.txt), and a hard-linked file (`ln file1 file2`).

## 6. Top 5 Risks & Mitigations
1. **Risk:** Stack overflow from extremely deep directory trees.
   **Mitigation:** The directory walk must use an explicit queue (iterative BFS/DFS) rather than function recursion.
2. **Risk:** Swift `String` allocations causing memory limits to blow up and trigger OOM kills.
   **Mitigation:** Store file names as raw `[UInt8]` bytes from the OS. Only convert to Swift `String` at the UI layer when the segment is actually rendered.
3. **Risk:** UI freezing due to millions of UI updates.
   **Mitigation:** The UI never sees the whole tree. `ScannerCore` calculates the geometries and only sends the ~5,000 visible arcs to SwiftUI.
4. **Risk:** Hard-link tracking (`Set<FileID>`) consumes massive memory.
   **Mitigation:** Only track inodes for files where the `stat` link count (`st_nlink`) is > 1.
5. **Risk:** `getattrlistbulk` dropping entries if the buffer is too small.
   **Mitigation:** Implement a robust fallback to `readdir` + `lstat` if `getattrlistbulk` returns an error or unsupported flag.
