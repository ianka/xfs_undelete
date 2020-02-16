# xfs_undelete
An undelete tool for the XFS filesystem.

## What does it?
*xfs_undelete* tries to recover all files on an XFS filesystem marked as deleted.
You may also specify a date or age since deletion, and file types to ignore or to recover exclusively.

*xfs_undelete* does some sanity checks on the files to be recovered.
This is done to avoid recovering bogus petabyte sized sparse files.
In addition, it does not recover anything unidentifiable (given you have the *file* utility installed) by default.
Specify *-i ""* on the command line if you want to recover those unidentifiable files.

The recovered file is stored on another filesystem in a subdirectory, by default *xfs_undeleted* relative to the current directory.
The filename cannot be recovered and thus, it is put as the time of deletion, the inode number, and a guessed file extension.
You have to check the recovered files you are interested in by hand and rename them properly.

## How does it work?
*xfs_undelete* traverses the inode B+trees of each allocation group, and checks the filesystem blocks holding inodes for the magic string *IN\0\0\3\2\0\0* that indicates a deleted inode.
Then, it tries to make sense of the extents stored in the inode (which XFS does not delete) and collect the data blocks of the file.

## Is it safe to use?
Given it only ever *reads* from the filesystem it operates on, yes.
It also remounts the filesystem read-only on startup so you don’t accidentally overwrite source data.
However, I don’t offer any warranty or liability. **Use at your own risk.**

## Prerequisites
*xfs_undelete* is a tiny Tcl script so it needs a Tcl interpreter.
It makes use of some features of Tcl-8.6, so you need at least that version.
The *tcllib* package is used for parsing the command line.
It also needs a version of *dd* which supports the *bs=*, *skip=*, *seek=*, *count=*, *conv=notrunc*, and *status=none* options.
That one from from GNU core utilities will do.
If the *file* utility and magic number files with MIME type support are installed (likely), *xfs_undelete* will use that to guess a file extension from the content of the recovered file. In short:

- tcl >= 8.6
- tcllib
- GNU coreutils

Optional:

- file (having magic number files with MIME type support)

In addition, you need enough space on another filesystem to store all the recovered files as they cannot be recovered in place.

## Limitations
- The way XFS deletes files makes it impossible to recover the filename or the path. You cannot undelete only certain files. The tool however has a mechanism only to recover files deleted since a certain date. See the -t option.
- The way XFS deletes files makes it impossible to recover heavily fragmented files. For typical 512 byte inodes, you can only recover files having at maximum 21 extents (of arbitrary size). Files with more extents cannot be recovered at all by this program.
- The way XFS deletes files makes it impossible to retrieve the correct file size. Most files will be padded with zeroes so they fit the XFS block size. Most programs do not bother anyway.

## How to use it

	# cd ~
	# xfs_undelete /dev/mapper/cr_data

This stores the recovered files from */dev/mapper/cr_data* in the directory *~/xfs_undeleted*.

	# xfs_undelete -o /mnt/external_harddisk /dev/sda3

This stores the recovered files from */dev/sda3* in the directory */mnt/external_harddisk*.

	# xfs_undelete -t 2020-01-01 /dev/sda3

This ignores files deleted before Jan 1st, 2020.

	# xfs_undelete -t -1hour /dev/sda3

This ignores files deleted more than one hour ago. The -t option accepts all dates understood by Tcl’s [clock scan] command.

	# xfs_undelete -i "" -t -1hour /dev/sda3

This recovers all files deleted not more than one hour ago, including “bin” files.

	# xfs_undelete -r "png gif" /dev/sda3

This only recovers png and gif files.

Please understand the file extensions *xfs_undelete* understands are guessed from the MIME type the *file* utility reports.
It is not neccessarily the same file extension the file had before you deleted it.

Please also remember *xfs_undelete* remounts the source filesystem read-only.
Once you found all the files you lost and want to put them in them place again, you have to remount it read-write by yourself.

## License
*xfs_undelete* is free software, written and copyrighted by
Jan Kandziora &lt;jjj@gmx.de&gt;. You may use, distribute and modify it under the
terms of the attached GPLv3 license. See the file LICENSE for details.
