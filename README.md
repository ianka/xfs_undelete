# xfs_undelete
An undelete tool for the XFS filesystem.

## What does it?
*xfs_undelete* tries to recover all inodes on an XFS filesystem marked as deleted.
It's rather dumb, it just looks for the magic string *IN\0\0\3\2\0\0* and considers those as deleted inodes.
Then, it tries to make sense of the extents stored in the inode (which XFS does not delete) and collect the data blocks of the file.
That file is then stored on another filesystem in a subdirectory, by default *xfs_undeleted* relative to the current directory.

## Is it safe to use?
Given it only ever *reads* from the filesystem it operates on, yes.
It also remounts the filesystem read-only on startup so you don’t accidentally overwrite source data.
However, I don’t offer any warranty or liability. **Use at your own risk.**

## Prerequisites
*xfs_undelete* is a tiny Tcl script so it needs a Tcl interpreter. It makes use of some features of Tcl-8.6, so you need at least that version. The *tcllib* package is used for parsing the command line. In addition, it needs the *xfs_db* tool from the *xfsprogs* package, and a version of *dd* which supports the *bs=*, *skip=*, *seek=*, and *count=* options. That one from from GNU core utilities will do. In short:

- tcl >= 8.6
- tcllib
- xfsprogs
- GNU coreutils

In addition, you need enough space on another filesystem to store all the recovered files as they cannot be recovered in place.

## Limitations
- The way XFS deletes files makes it impossible to recover the filename or the path. You cannot undelete only certain files. The tool however has a mechanism only to recover files deleted since a certain date. See the -t option.
- The way XFS deletes files makes it impossible to recover heavily fragmented files. For typical 512 byte inodes, you can only recover files having at maximum 21 extents (of arbitrary size). Files with more extents cannot be recovered at all by this program.
- It's rather slow. Expect 2 GB scanned per minute. I don’t do this often enough to see a problem.

## How to use it

	# cd ~
	# xfs_undelete /dev/mapper/cr_data

This stores the recovered files from */dev/mapper/cr_data* in the directory *~/xfs_undeleted*.

	# xfs_undelete -o /mnt/external_harddisk /dev/sda3

This stores the recovered files from */dev/sda3* in the directory */mnt/external_harddisk*.

	# xfs_undelete -s 1234567890 /dev/sda3

This starts recovery with filesystem block *1234567890*. You can resume an aborted recovery this way.

	# xfs_undelete -t 2020-01-01 /dev/sda3

This ignores files deleted before Jan 1st, 2020.

	# xfs_undelete -t -1week /dev/sda3

This ignores files deleted more than one week ago. The -t option accepts all dates understood by Tcl’s [clock scan] command.


Please remember *xfs_undelete* remounts the source filesystem read-only.
Once you found all the files you lost and want to put them in them place again, you have to remount it read-write by yourself.

## License
*xfs_undelete* is free software, written and copyrighted by
Jan Kandziora <jjj@gmx.de>. You may use, distribute and modify it under the
terms of the attached GPLv3 license. See the file LICENSE for details.
