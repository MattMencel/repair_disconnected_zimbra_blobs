repair_disconnected_zimbra_blobs
================================

Script to repair disconnected Zimbra mail blobs.

repair_disconnected_blobs.rb --help                             
Options:
     --path, -p <s>:   Volume path
  --account, -a <s>:   Account
         --test, -t:   Test Mode - DO NOT UPDATE DB
         --help, -h:   Show this message


- Must be run as the Zimbra user.
- Must zmsetvars first.  The script will prompt with the correct command you need to run.
- Must set your mail domain in one part of the script.  Grep it for '@test.edu' to see where.


BACK STORY:  We had a SAN failure in which both controllers went offline, thus
ripping the storage out from underneath our hosts.  This badly corrupted the
MySQL database for Zimbra as well as caused some disk corruption that had to be
repaired with e2fsck.

Once we had the SAN back online we brought the Zimbra mailbox server online and
began the slow process of restoring the database from backup and rolling in the
redologs.  We did not discover until after the restore was complete that the
two HSM volumes, though mounted in the file system, were not connected in
Zimbra as zmvolumes (zmvolume -l).  Thusly....it seems as if during the DB
restore...because Zimbra did not list the two HSM volumes anymore....it simply
reconnected all the mail blob entries in the DB for all the blob files stored
on the HSM volumes to the primary STORE volume.  This meant that about 95% of
our mail messages on this mailbox no longer pointed to blob files in the
correct location, and users got the dreaded "no such blob" error when trying to
open one of the affected mail messages.

So....we wrote this script to fix the problem.  It took about 5 hours to fix
3300+ accounts with around 900GB of mis-directed blob data.

Use/share/improve...

Matt
