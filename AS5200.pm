### AS5200.pm
### PERL module for talking to a Cisco AS5200 access router
#########################################################

package RAS::AS5200;
$VERSION = "1.00";

# The new method, of course
sub new {
   my $class = shift ;
   my $confarray = {} ;
   %$confarray = @_ ;
   bless $confarray ;
}


sub printenv {
   my($confarray) = $_[0];
   while (($key,$value) = each(%$confarray)) { print "$key = $value\n"; }
}


sub run_command {
   my($confarray) = shift;
   use Net::Telnet ;
   my($session,@returnlist,$command);

   while ($command = shift) {
      my(@output);
      $session = new Net::Telnet (-prompt => '/as5200[#>]$/');
      $session->open($confarray->{hostname});
      $session->waitfor('/Password: $/');
      $session->print("");
      $session->waitfor('/Password: $/');
      $session->print($confarray->{password});
      $session->waitfor($session->prompt);

      # If the command was prefixed with the ENABLE
      # keyword, go into enabled mode
      if ($command =~ s/^ENABLE //) {
         $session->print("enable");
         $session->waitfor('/Password: $/');
         $session->print($confarray->{enablepassword});
         $session->waitfor($session->prompt);
      }
      $session->print($command);

      while (1) {
         local($line); $session->print(""); $line = $session->getline;
         if ($line eq "[confirm]") { $session-print("y"); next; }
         if ($line =~ /^as5200[#>]/) { $session->print("exit"); $session->close; last; }
         $line =~ s/^\s?--More--\s*\010+\s+\010+//;
         push(@output, $line);
      }

      shift(@output); # Trim the echoed command
      push(@returnlist, \@output);
   } # end of shifting commands

   # We're returning a list of references to lists.
   # Each ref points to an array containing the returned text
   # from the command, and the list of refs corresponds
   # to the list of commands we were given
   return(@returnlist);
} # end of run_command


sub usergrep {
   my($confarray) = $_[0];
   my($username) = $_[1]; return unless $username;
   my($output) = &run_command($confarray,'show users');
   my(@ports);

   foreach (@$output) {
      local($port,$user);
      next unless (/^\s+\d+ tty \d+\s/ || /^\s+Se\d+\:\d+\s/);
      $port = unpack("x0 a12", $_) ; $port =~ s/^\s*\d* //; $port =~ s/\s*$//;
      $user = unpack("x12 a10", $_); $user =~ s/^\s*//; $user =~ s/\s*$//;
      ($user eq $username) && push(@ports,$port);
   }
   return(@ports);
}


sub portusage {
   my($confarray) = $_[0];
   my($interfaces,$connections) = &run_command($confarray,'sho isdn status','show users');
   my(@users);
   my($usedports); $usedports = 0;

   $usedports = 23 * scalar(grep(/^ISDN Serial\S+ interface$/, @$interfaces));

   foreach (@$connections) {
      local($port,$user);
      next unless (/^\s+\d+ tty \d+ / || /^\s+Se\d+\:\d+ /);
      $user = unpack("x12 a10", $_); $user =~ s/^\s*(\S+)\s*$/$1/;
      next if ($user =~ /^\s*$/);
      push(@users,$user);
   }

   return($usedports,@users);
}


sub userkill {
   my($confarray) = $_[0];
   my($username); $username = $_[1]; return unless $username;
   my(@killcommands);
   my(@ports) = &usergrep($confarray,$username);
   return() unless @ports;

   foreach (@ports) {
      if (/^tty/)   { push(@killcommands, "ENABLE clear line $_"); }
      elsif (/^Se/) { push(@killcommands, "ENABLE clear int $_"); }
   }

   &run_command($confarray,@killcommands);
   return(@ports);
}


#############################################################
1;#So PERL knows we're cool
__END__;

=head1 NAME

RAS::AS5200.pm - PERL Interface to Cisco AS5200 Access Router

Version 1.00, December 17, 1999

Gregor Mosheh (stigmata@blackangel.net)

=head1 SYNOPSIS

B<RAS::AS5200> is a PERL 5 module for interfacing with a Cisco AS5200 access router. Using this module, one can very easily construct programs to find a particular user in a bank of AS5200s, disconnect users, get usage statistics, or execute arbitrary commands on a AS5200.


=head1 PREREQUISITES AND INSTALLATION

This module uses Jay Rogers' B<Net::Telnet module>. If you don't have B<Net::Telnet>, get it from CPAN or this module won't do much for you.

Installation is easy, thanks to MakeMaker:

=over 4

=item 1.

"perl Makefile.PL && make"

=item 2.

"make test" to run the test suite. Check the test output. It should seem correct. If there are errors, check the hostname and passwords and try again.

=item 3.

If all is good, do a "make install"

=item 4.

Check out the examples in this documentation.

=back

=head1 DESCRIPTION

At this time, the following methods are implemented:

=over 4

=item creating an object with new

Call the new method while supplying the  "hostname", "login", "password", and "enablepassword" hash, and you'll get an object reference returned.

   Example:
      use RAS::AS5200;
      $foo = new RAS::AS5200(
         hostname => 'dialup1.example.com',
         login => '!root',
         password => 'mysecret'
      );

At this time, the enablepassword is only required for the userkill() method, and can be undefined if you don't intend to use userkill()


=item printenv

This is for debugging only. It prints to STDOUT a list of its configuration hash, e.g. the hostname, login, and password. The printenv method does not return a value.

   Example:
      $foo->printenv;


=item run_command

This takes a list of commands to be executed on the AS5200, connects to the AS5200 and executes the commands, and returns a list of references to arrays containg the text of each command's output. 

Repeat: It doesn't return an array, it returns an array of references to arrays. Each array contains the text output of each command. Think of it as an array-enhanced version of PERL's `backtick` operator.

Some router functions (e.g. rebooting) ask for confirmation - confirmation will be automatically supplied by the module's interface routines.

   Example:
      # Execute a command and print the output
      $command = 'list conn';
      ($x) = $foo->run_command($command);
      print "Output of command \'$command\':\n", @$x ;

   Example:
      # Execute a string of commands
      # and show the output from one of them
      (@output) = $foo->run_command('list interface','list con');
      print "Modems:\n@$output[0]\n\n";;
      print "Current connections:\n@$output[1]\n\n";;

In Cisco-land, some functions are only available in enabled mode. To specify that a command should be run in enabled mode, prefix the command with "ENABLE " - that's all caps and a single space between the ENABLE and the rest of the command.

   Example:
      # Reboot the router
      $foo->run_command('ENABLE reload');

=item usergrep

Supply a username as an argument, and usergrep will return an array of ports on which that user was found. Internally, this does a run_command("list connections") and parses the output.

   Example:
      @ports = $foo->usergrep('gregor');
      print "User gregor was found on ports @ports\n";


=item userkill

This does a usergrep, but with a twist: it disconnects the user by resetting the modem on which they're connected. Like usergrep, it returns an array of ports to which the user was connected before they were reset.  This is safe to use if the specified user is not logged in.

   Examples:
      @foo = $foo->userkill('gregor');
      print "Gregor was on ports @foo - HA HA!\n" if @ports ;

      @duh = $foo->userkill('-');
      print "There were ", scalar(@duh), " ports open.\n";


=item portusage

This returns an array consisting of 2 items: The 1st element is the number of ports. The rest is a list of users who are currently online.

   Examples:
      ($ports,@people) = $foo->portusage;
      print "There are $ports total ports.\n";
      print "There are ", scalar(@people), "people online.\n";
      print "They are: @people\n";

      ($ports,@people) = $foo->portusage;
      print "Ports free: ", $ports - scalar(@people), "\n";
      print "Ports used: ", scalar(@people), "\n";
      print "Ports total: ", $ports, "\n";


=head1 EXAMPLE PROGRAMS

portusage.pl - Prints a summary of port usage on a bank of modems

use RAS::AS5200;
$used = $total = 0;
foreach ('dialup1.example.com','dialup2.example.com','dialup3.example.com') {
   $foo = new RAS::AS5200(
      hostname => $_,
      login => '!root',
      password => 'mysecret'
   );

   local($ports,@ports) = $foo->portusage;
   $total += $ports;
   $used += scalar(@ports);
}

print "$used out of $total ports are in use.\n";

###

usergrep.pl - Finds a user on a bank of modems

($username) = @ARGV;
die "Usage: $0 <username>\nFinds the specified user.\n" unless $username ;

use RAS::AS5200;
foreach ('dialup1.example.com','dialup2.example.com','dialup3.example.com') {
   $foo = new RAS::AS5200(
      hostname => $_,
      login => '!root',
      password => 'mysecret'
   );

   @ports = $foo->usergrep($username);
   (@ports) && print "Found user $username on $_ ports @ports\n";
}

###

userkill.pl - Kick a user off a bank of modems. Makes a great cron job. ;)

($username) = @ARGV;
die "Usage: $0 <username>\nDisconnects the specified user.\n" unless $username ;

use RAS::AS5200;
foreach ('dialup1.example.com','dialup2.example.com','dialup3.example.com') {
   $foo = new RAS::AS5200(
      hostname => $_,
      login => '!root',
      password => 'mysecret'
   );

   @ports = $foo->userkill($username);
   (@ports) && print "$_ : Killed ports @ports\n";
}


=head1 BUGS

In userkill(), I have not yet tested the killing of SeA:B addresses, which are assigned instead of tty addresses to ISDN users. When I get permission to nuke some ISDN customers, I'll test this. The killing of analog modem users (assigned tty addresses) seems to work perfectly.

This is one of my first tries at doing PERL 5 stuff, having been satisfied for so many years with using only the PERL 4 features. Though this module seems to work without any problems, the code is probably kinda weak in places and could stand optimization. Any suggestions will be appreciated and credit will be given.

More features are forthcoming. I realize that the existing set of functions is a bit bare. If you need special features, please ask and I'll work on them in my spare time. Alternately, you can write it yourself and send it in and I'll gladly incorporate it and give credit. And there's always the run_command method.

=head1 CHANGES IN THIS VERSION

1.00     First released version of RAS::AS5200. The AS5200 doesn't have a lot of cool features like the PortMaster or the HiPerARC, so some of my method implementations are really lame. Blame Cisco for making a lousy interface to a nice router and for not educating their tech support in its usage. If anyone's more familiar with the AS5200, I'd appreciate any suggestions.

=head1 LICENSE AND WARRANTY

Where would we be if Larry Wall were tight-fisted with PERL itself? For God's sake, it's PERL code. It's free!

This software is hereby released into the Public Domain, where it may be freely distributed, modified, plagiarized, used, abused, and deleted without regard for the original author.

Bug reports and feature requests will be handled ASAP, but without guarantee. The warranty is the same as for most freeware:
   It Works For Me, Your Mileage May Vary.

=cut

