### AS5200.pm
### PERL module for talking to a Cisco AS5200 access router
#########################################################

package RAS::AS5200;
$VERSION = "1.02";

use strict "subs"; use strict "refs";

# This uses Net::Telnet to connect to the RAS
use Net::Telnet ;

# The name $ras will be used consistently as the
# reference to the RAS::HiPerARC object we're handling

# The constructor method, of course
sub new {
   my($class) = shift ;
   my($ras) = {} ;
   %$ras = @_ ;
    $ras->{'VERSION'} = $VERSION;
   bless($ras);
}


# for debugging - printenv() prints to STDERR
# the entire contents of %$ras
sub printenv {
   my($ras) = shift;
   while (($key,$value) = each(%$ras)) { warn "$key = $value\n"; }
}


# This runs the specified commands on the router and returns
# a list of refs to arrays containing the commands' output
sub run_command {
   my($ras) = shift;
   my(@returnlist);

   while ($command = shift) {
      my($session) = new Net::Telnet (-prompt => '/as5200[#>]$/');
      $session->errmode("return");
      $session->open($ras->{hostname});
      if ($session->errmsg) {
         warn "ERROR: ",ref($ras),' - ',$session->errmsg,"\n"; return(); }
      $session->waitfor('/Password: $/');
      $session->print("");
      $session->waitfor('/Password: $/');
      $session->print($ras->{password});
      $session->waitfor($session->prompt);
      if ($session->errmsg) {
         warn "ERROR: ",ref($ras),' - ',$session->errmsg,"\n"; return(); }
      my(@output);

      # If the command was prefixed with the ENABLE
      # keyword, go into enabled mode
      if ($command =~ s/^ENABLE //) {
         $session->print("enable");
         $session->waitfor('/Password: $/');
         $session->print($ras->{enablepassword});
         $session->waitfor($session->prompt);
         if ($session->errmsg) {
            warn "RAS::AS5200 ERROR: ", $session->errmsg, "\n"; return();
         }
      }
      $session->print($command);

      while (1) {
         $session->print(""); my($line) = $session->getline;
         if ($session->errmsg) {
            warn "ERROR: ",ref($ras),' - ',$session->errmsg,"\n"; return(); }
         if ($line eq "[confirm]") { $session->print("y"); next; }
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


# usergrep() - takes a username and returns an array of
# ports on which the user was found
sub usergrep {
   my($ras) = shift;
   my($username) = shift; return() unless $username;
   if ($ras->{truncateusernames}) { $username = substr($username,0,10); }
   my($output) = $ras->run_command('show users');
   my(@ports);

   foreach (@$output) {
      local($port,$user);
      next unless (/^\s+\d+ tty \d+\s/ || /^\s+Se\d+\:\d+\s/);
      $port = unpack("x0 a12", $_) ; $port =~ s/^\s*\d* //; $port =~ s/\s*$//;
      $user = unpack("x13 a10", $_); $user =~ s/^\s*//; $user =~ s/\s*$//;
      ($user eq $username) && push(@ports,$port);
   }
   return(@ports);
}


# portusage() returns a list: # of ports, list of users
sub portusage {
   my($ras) = shift;
   my($interfaces,$connections) = $ras->run_command('sho isdn status','show users');
   my(@users, $totalports);

   $totalports = 23 * scalar(grep(/^ISDN Serial\S+ interface$/, @$interfaces));

   foreach (@$connections) {
      my($port,$user);
      next unless (/^\s+\d+ tty \d+ / || /^\s+Se\d+\:\d+ /);
      $user = unpack("x13 a10", $_); $user =~ s/^\s*(\S+)\s*$/$1/;
      next if ($user =~ /^\s*$/);
      push(@users,$user);
   }

   return($totalports,@users);
}


# This does a usergrep() and then disconnects the specified user
sub userkill {
   my($ras) = shift;
   my($username); $username = shift; return() unless $username;
   if ($ras->{truncateusernames}) { $username = substr($username,0,10); }
   my(@ports) = $ras->usergrep($username);
   return('') unless @ports;

   my(@killcommands);
   foreach (@ports) {
      if (/^tty/)   { push(@killcommands, "ENABLE clear line $_"); }
      elsif (/^Se/) { push(@killcommands, "ENABLE clear int $_"); }
   }

   $ras->run_command(@killcommands);
   return(@ports);
}


#############################################################
1;#So PERL knows we're cool
__END__;

=head1 NAME

RAS::AS5200.pm - PERL Interface to Cisco AS5200 Access Router

Version 1.02, January 17, 2000

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

Call the new method while supplying the "hostname", "login", "password", and "enablepassword" values, and you'll get an object reference returned.

   Example:
      use RAS::AS5200;
      $foo = new RAS::AS5200(
         hostname => 'dialup1.example.com',
         login => '!root',
         password => 'mysecret',
         truncateusernames => 'true'
      );

At this time, the enablepassword is only required for the userkill() method, and doesn't need to be defined if you don't intend to use userkill().

Since there's no point in dynamically changing the hostname, login, etc. these settings are static and must be supplied to the constructor. No error will be returned if these settings are not specified, but your program will likely not get very far without at least a hostname, and a correct password tends to help, too. ;)

If the "truncateusernames" option is set to non-null, then usernames supplied to user-seeking functions such as userkill() and usergrep() will be internally truncated to 10 characters. This is to work around a "feature" of the AS5200 that only the first 10 characters of a login name are displayed, which would cause usergrep('johnjjschmidt') to never work, as the AS5200 displays the login name as 'johnjjschm'. See the TRUNCATING USER NAMES section for more discussion on this.


=item printenv

This is for debugging only. It prints to STDOUT a list of its configuration hash, e.g. the hostname, login, and password. The printenv method does not return a value.

   Example:
      $foo->printenv;


=item run_command

This takes a list of commands to be executed on the AS5200, executes the commands on the AS5200, and returns a list of references to arrays containg the text of each command's output. 

Repeat: It doesn't return an array, it returns an array of references to arrays. Each array contains the text output of each command. Think of it as an array-enhanced version of PERL's `backtick` operator.

Some router functions (e.g. rebooting) ask for confirmation - confirmation will be automatically supplied by the module's interface routines.

   Example:
      # Execute a command and print the output
      $command = 'show modems';
      ($x) = $foo->run_command($command);
      print "Output of command \'$command\':\n", @$x ;

   Example:
      # Execute a string of commands
      # and show the output from one of them
      (@output) = $foo->run_command('show isdn status','show modems');
      print "Modems:\n@$output[0]\n\n";;
      print "Current connections:\n@$output[1]\n\n";;

In Cisco-land, some functions are only available in enabled mode. To specify that a command should be run in enabled mode, prefix the command with "ENABLE " - that's all caps and a single space between the ENABLE and the rest of the command.

   Example:
      # Reboot the router
      $foo->run_command('ENABLE reload');


=item usergrep

Supply a username as an argument, and usergrep will return an array of ports on which that user was found (thus, an empty list if they weren't found). An undefined value is returned if no username was supplied. Internally, this does a run_command('show users') and processes the output.

   Example:
      @ports = $foo->usergrep('gregor');
      print "User gregor was found on ports @ports\n";


=item userkill

This does a usergrep, but with a twist: it disconnects the user by resetting the modem on which they're connected. Like usergrep, it returns an array of ports to which the user was connected before they were reset (or an empty list if they weren't found). The undefined value is returned if no username is supplied.

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
   foreach ('dialup1.example.com','dialup2.example.com') {
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
   foreach ('dialup1.example.com','dialup2.example.com') {
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
   foreach ('dialup1.example.com','dialup2.example.com') {
   $foo = new RAS::AS5200(
      hostname => $_,
      login => '!root',
      password => 'mysecret'
   );

   @ports = $foo->userkill($username);
   (@ports) && print "$_ : Killed ports @ports\n";
}


=head1 TRUNCATING USER NAMES

A "feature" of the Cisco AS5200 is that only the first 10 characters of login names are displayed. As such, doing a usergrep('johnjjschmidt') would never find the fellow, as the AS5200 truncates the username to 'johnjjschm'.

To work around this, you may set the "truncateusernames" flag in your constructor (see above). This will cause user-matching functions such as usergrep and userkill to internally truncate usernames to 10 characters for matching purposes. This means that usergrep('johnjjschmidt') would internally be treated as usergrep('johnjjschm') so that it would match.

So, you have your choice of two evils. If you don't enable username truncation, you'll miss users with login names over 10 characters in length. If you enable it, you could accidentally userkill user 'johnjjschm' when you meant to kill 'johnjjschmidt'. Sorry - Cisco screwed up and we get to suffer for it.


=head1 BUGS

The set of functions is somewhat bare. Since we use this for port usage monitoring, new functions will be added slowly on an as-needed basis. If you need some specific functionality let me know and I'll see what I can do. If you write an addition for this, please send it in and I'll incororate it and give credit.

I make some assumptions about router prompts based on what I have on hand for experimentation. If I make an assumption that doesn't apply to you (e.g. all prompts are /^as5200[#>]\s+$/) then you'll get "pattern match timed out" errors. Check the regexps in the loop within run_command, and make sure your prompt fits this regex. If not, either fix the regex and/or (even better) PLEASE send me some details on your prompt and what commands you used to set your prompt so I can experiment with it. A similar situation can occur if you use the wrong RAS module to connect to a router - a Livingston PortMaster, for example, has a different prompt than a AS5200 - if you accidentally point to a PortMaster using RAS::AS5200, you'll get pattern match timeouts.


=head1 CHANGES IN THIS VERSION

1.02     Cleaned up the code substantially. Fixed a "bug" that truncated usernames at 8 characters. Added the "truncateusernames" option. Tested the userkill() function on ISDN clients - works.

1.01     Improved the error handling a tad. Touched up the docs.

1.00     First released version of RAS::AS5200.


=head1 LICENSE AND WARRANTY

Where would we be if Larry Wall were tight-fisted with PERL itself? For God's sake, it's PERL code. It's free!

This software is hereby released into the Public Domain, where it may be freely distributed, modified, plagiarized, used, abused, and deleted without regard for the original author.

Bug reports and feature requests will be handled ASAP, but without guarantee. The warranty is the same as for most freeware:
   It Works For Me, Your Mileage May Vary.

=cut

