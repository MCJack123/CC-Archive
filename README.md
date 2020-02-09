# CC-Archive
Various archiving/compression programs and libraries for ComputerCraft. All libraries should be loaded with `require()`. Everything in this repository is under public domain unless otherwise specified, though it would be nice if you link back to this repo if you use one of the libraries.

## ar
Program & library for accessing \*.a files. Uses System V/GNU-style archives.
### Library
* *table* ar.load(*string* path): Loads an archive into a file.
  * path: The absolute path to an ar archive
  * Returns: A list of file entries with the format:
    * *string* name: The name of the file
    * *number* timestamp: The UNIX timestamp of the last modified time
    * *number* owner: The UID of the file owner
    * *number* group: The GID of the file owner
    * *number* mode: The octal file permissions of the file
    * *string* data: The actual file's data
* *nil* ar.write(*table* entry, *string* path): Writes an ar file entry to a file.
  * entry: A file entry as loaded with `ar.load()`
  * path: The absolute path to the output file
* *nil* ar.extract(*table/string* archive, *string* path): Writes an entire archive to a directory.
  * archive: Either an archive loaded with `ar.load()` or the absolute path to an archive
  * path: The absolute path to the output directory
* *table* ar.read(*string* path): Reads a file into an ar file entry.
  * path: The absolute path to the file to load
  * Returns: An ar file entry with the contents of the file
* *table* ar.pack(*string* path): Loads files in a directory into a list of ar entries.
  * path: The absolute path to the directory to load
  * Returns: A list of file entries that can be used by `ar.save()`
* *nil* ar.save(*table* data, *string* path): Writes a list of file entries to an ar archive.
  * data: The list of file entries to write
  * path: The absolute path of the ar file to save
### CLI
Functions similarly to GNU/BSD `ar`, with the following options:
```
commands:
  d            - delete file(s) from the archive
  p            - print file(s) found in the archive
  q            - quick append file(s) to the archive
  r            - replace existing or insert new file(s) into the archive
  t            - display contents of archive
  x            - extract file(s) from the archive
modifiers:
  [c]          - do not warn if the library had to be created
  [T|f]        - truncate file
  [u]          - only replace files that are newer than current archive contents
  [v]          - be verbose
```

## archive
Library for creating ComputerCraft-friendly archives.
### Format
Archives are gzipped serialized Lua tables with the file name as the key and the file/directory data as the value. File data is represented by a string with the data while directory data is represented as a table with the same format as the root directory.

Archives returned by the library are represented as filesystem objects with the same methods as the `fs` library, with two extra methods: `write(path)` writes the archive to a file, and `extract(path)` extracts the file in the archive to a directory.
### Library
* *table* archive.new(): Returns a new archive filesystem object.
* *table* archive.load(*string* path): Loads a directory into a new archive.
  * path: The absolute path to the directory to load
  * Returns: A new filesystem object with the contents of the directory
* *table* archive.read(*string* path): Reads an archive file into a new filesystem object.
  * path: The absolute path to the archive to load
  * Returns: A new filesystem object with the contents of the archive
* *table* archive(\[*string* path\]): Chooses the most appropriate of the three functions above to use on the specified path.
  * path: The path to an archive or directory to load
  * Returns: If path is nil, returns `archive.new()`; if path points to a directory, returns `archive.load(path)`; if path points to a file, returns `archive.read(path)`

## arlib
Library for loading libraries from an ar archive.
### Library
* *boolean* arlib.loadAPIs(*string* path, ...): Loads all libraries in an archive...? Not sure what this does exactly.
* *any* arlib.require(*string* path, *string* name): Loads a library from an archive using `package.path`.
  * path: A file name specifier for the archive to load. `package.path` will be used to find the correct path for the archive.
  * name: The name of the library to load from the archive, may or may not include extension
  * Returns: The return value of the loaded library, or nil if it couldn't be found
  
## gzip
Program that implements GNU gzip in CC.
### CLI
```
Usage: gzip [OPTION]... [FILE]
Compress or uncompress FILEs (by default, compress FILES in-place).

  -c, --stdout      write on standard output, keep original files unchanged
  -d, --decompress  decompress
  -f, --force       force overwrite of output file
  -h, --help        give this help
  -k, --keep        keep (don't delete) input files
  -l, --list        list compressed file contents
  -t, --test        test compressed file integrity
  -v, --verbose     verbose mode
  -V, --version     display version number
  -1, --fast        compress faster
  -9, --best        compress better

With no FILE, or when FILE is -, read standard input.
```

## LibDeflate
Modified version of [LibDeflate](https://github.com/SafeteeWow/LibDeflate) that works with ComputerCraft. See the official repo for more details.

## muxzcat
Version of [pts's muxzcat program](https://github.com/pts/muxzcat) ported to Lua. Decompresses XZ/LZMA files.
### Library
*boolean, number* muxzcat.DecompressXzOrLzmaFile(*string/FILE* input, *string/FILE* output): Decompresses files from/to disk.
  * input: Path or IO file to read from
  * output: Path or IO file to write to
  * Returns: Whether the task succeeded, and an error code if it failed
*string/nil, number* muxzcat.DecompressXzOrLzmaString(*string* input): Decompresses XZ/LZMA data from a string.
  * input: Contents of file to decompress
  * Returns: The decompressed data, or nil on failure plus an error code
*string* muxzcat.GetError(*number* code): Returns a somewhat human readable string for an error code.
  * code: The error code as returned from either decompress function
  * Returns: A short all-caps string that describes the error
*table* muxzcat.Errors: Table mapping error strings to error codes.

## tar
Program & library for accessing tar archives. Uses UStar-style archives.
### Library
* *table* tar.load(*string* path\[, *boolean* noser\[, *boolean* rawdata\]\]): Loads a tar archive into a table.
  * path: The absolute path to a tar file, or the contents of a tar file if rawdata is set
  * noser: Set to true to not automatically unserialize tar entries
  * rawdata: Set to true to read raw archive data from path instead of from a file
  * Returns: Either a list of tar entries or a hierarchy of tar entries, depending on noser. A tar entry is in the format:
    * *string* name: The name of the file
    * *number* mode: The octal UNIX permissions of the file
    * *number* owner: The UID of the file owner
    * *number* group: The GID of the file owner
    * *number* timestamp: The UNIX timestamp of the file's modification data
    * *number* type: The type of file (0 = file, 5 = directory, others are irrelevant in CC)
    * *string* link: If the file is a link, the target of the link
    * *string* data: The actual file data
    * Extended attributes:
      * *string* ownerName: The username of the file owner
      * *string* groupName: The name of the group of the file owner
      * *table* deviceNumber: If the file is a device reference, a two-entry table with the device's major and minor IDs
* *nil* tar.extract(*table* data, *string* path): Extracts the contents of a tar hierarchy to a directory.
  * data: The tar archive to extract
  * path: The absolute path to the destination directory
* *table* tar.read(*string* base, *string* path): Reads a file into a tar entry.
  * base: The base directory to read from (this will not be stored in the archive)
  * path: The path to the file, relative to the base path (this will be stored)
  * Returns: A single tar entry with the contents of the file
* *table* tar.pack(*string* path): Reads a directory into a tar hierarchy.
  * base: The directory to read from
  * Returns: A hierarchical tar table with the contents of the directory
* *nil* tar.save(*table* data, *string* path\[, *boolean* noser\]): Saves tar entries to a tar archive.
  * data: The tar entries to save
  * path: The absolute path to the tar file to save to
  * noser: When false (or not present), data is a hierarchy; when true, data is a serialized list of entries
* *table* tar.unserialize(*table* data): Unserializes a list of tar entries into a hierarchy.
  * data: A list of tar entries
  * Returns: A hierarchical list of file/directory entries
* *table* tar.serialize(*table* data): Serializes a hierarchical table of tar entries into a list.
  * data: A hierarchy of tar entries
  * Returns: A list of tar entries
### CLI
```
Usage: tar [OPTION...] [FILE]...
CraftOS 'tar' saves many files together into a single tape or disk archive, and
can restore individual files from the archive.

Examples:
  tar -cf archive.tar foo bar  # Create archive.tar from files foo and bar.
  tar -tvf archive.tar         # List all files in archive.tar verbosely.
  tar -xf archive.tar          # Extract all files from archive.tar.

 Local file name selection:

      --add-file=FILE        add given FILE to the archive (useful if its name
                             starts with a dash)
  -C, --directory=DIR        change to directory DIR
      --no-null              disable the effect of the previous --null option
      --no-recursion         avoid descending automatically in directories
      --null                 -T reads null-terminated names; implies
                             --verbatim-files-from
      --recursion            recurse into directories (default)
  -T, --files-from=FILE      get names to extract or create from FILE
  
 Main operation mode:

  -A, --catenate, --concatenate   append tar files to an archive
  -c, --create               create a new archive
  -d, --diff, --compare      find differences between archive and file system
      --delete               delete from the archive (not on mag tapes!)
  -r, --append               append files to the end of an archive
  -t, --list                 list the contents of an archive
  -u, --update               only append files newer than copy in archive
  -x, --extract, --get       extract files from an archive

 Overwrite control:

  -k, --keep-old-files       don't replace existing files when extracting,
                             treat them as errors
      --overwrite            overwrite existing files when extracting
      --remove-files         remove files after adding them to the archive
  -W, --verify               attempt to verify the archive after writing it

 Device selection and switching:

  -f, --file=ARCHIVE         use archive file or device ARCHIVE
   
 Device blocking:

  -i, --ignore-zeros         ignore zeroed blocks in archive (means EOF)
  
 Compression options:

  -z, --gzip, --gunzip, --ungzip   filter the archive through gzip
  
 Local file selection:

  -N, --newer=DATE-OR-FILE, --after-date=DATE-OR-FILE
                             only store files newer than DATE-OR-FILE
  
 Informative output:

  -v, --verbose              verbosely list files processed
  
 Other options:

  -?, --help                 give this help list
      --usage                give a short usage message
      --version              print program version
```

## unxz
Extracts an XZ file.
### CLI
```
Usage: unxz [OPTION]... [FILE]...
Decompress FILEs in the .xz format.

  -k, --keep         keep (don't delete) input files
  -f, --force        force overwrite of output file
  -c, --stdout       write to standard output and don't delete input files
  -h, --help         display this help and exit
  -V, --version      display the version number and exit

Report bugs to https://github.com/MCJack123/CC-Archive/issues.
Uses JackMacWindows's Lua port of muxzcat. Licensed under GPL v2.0.
```
