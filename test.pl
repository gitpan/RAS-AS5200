#!/usr/bin/perl
# test script for RAS::AS5200
#######################################################


print <<EOF;

Test Suite for RAS::AS5200
EOF

### Get the list of AS5200s to scan/test
print <<EOF;

The tests will connect to a AS5200
and run some benign commands to verify that 
things are working properly.
Enter the hostname or IP address of a
AS5200 that will be used for the tests.
Enter nothing to skip the tests.
EOF

print "Hostname or IP of AS5200: ";
chomp($pm = <STDIN>);
exit unless $pm;


print <<EOF;

Please enter the password used to log into 
the AS5200 for the tests.
EOF

print "Password for AS5200: ";
chomp($password = <STDIN>);


print <<EOF;

The usergrep() test looks for a specified user on a bank
of RAS devices. The userkill() function will look for
the specified user and knock them offline.
Specify here the user that will be located
and terminated. You will also be asked to enter
the Enable password to the AS5200. Enter nothing for 
these tests to be skipped.
EOF

print "Username for seek/kill tests: ";
chomp($testuser = <STDIN>);
print "Enable password for seek/kill tests: ";
chomp($enablepassword = <STDIN>);
print "\n\n";


######################################################
### And now that we have our data, the actual tests

use RAS::AS5200;

### Create a new instance
print "### Testing new() method for host $pm\n\n";
$foo = new RAS::AS5200(
   hostname => $pm,
   password => $password,
   enablepassword => $enablepassword,
);
die "ERROR: Couldn't create object. Stopped " unless $foo;
print "OK.\n\n";

print "### Testing the printenv() method:\n";
$foo->printenv;
print "\n\n";

print "### Testing the run_command() method:\n";
($x,$y) = $foo->run_command('show modem','show users');
print "Output of \'show modems\' on $pm:\n@$x\n\n";
print "Output of \'show users\' on $pm:\n@$y\n\n";

print "### Testing portusage() method:\n";
@x = $foo->portusage;
print "There are ", shift(@x), " modems in all.\n";
print "There are ", scalar(@x), " users online. ";
print "They are:\n@x\n\n";

if ($testuser) {
   print "### Testing usergrep() method on user $testuser\n";
   @x = $foo->usergrep($testuser);
   print "Found user $testuser on $pm ports: @x\n\n" if @x;
}
else { print "### Skipping usergrep() test\n"; }

if ($testuser) {
   print "### Testing userkill() method on user $testuser\n";
   @x = $foo->userkill($testuser);
   print "Killed user $testuser on $pm ports: @x\n\n" if @x;
}
else { print "### Skipping userkill() test\n"; }

print "Finished with tests.\n";


