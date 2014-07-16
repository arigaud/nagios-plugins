#!/usr/bin/perl -w
#
# check_bes5.pl - nagios plugin 
# Perl version of Philipp Deneu bash script
# based on perl plugin snmp template
# see http://wiki.monitoring-portal.org/nagios/plugins/perl_plugin_template
#
# Copyright (C) 2014 Alexandre Rigaud <arigaud.prosodie.cap@free.fr>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# Report bugs to:  nagiosplug-help@lists.sourceforge.net
#
# 25.06.2014 Version 1.0.0 : First release
#
# what's news ?
# - full perl script
# - could be execute in local or remote
# - add multi-instances tests
#

use strict;
use File::Basename;
use Getopt::Long;
use vars qw($PROGNAME $VERSION);
use lib "/usr/local/nagios/libexec";
use utils qw ($TIMEOUT %ERRORS &print_revision &support);
use Net::SNMP;
use lib "/opt/adm-mon-3.1/perl-5.8.8/lib/site_perl/5.8.8";
use Pod::Usage;

$PROGNAME = basename($0);
my $RELEASE = 'v20140625';
$VERSION = 'Revision: 1.0.0 ' . $RELEASE. ' ';

## Arguments
my ($hostname, $community, $port, $protocol, $timeout, $query, $warn, $crit, $help, $version)  = parse_args();

##Variables
my ($result, $message, $age, $size, $st, $state, $string, $oid, $value);

## SNMP
my ($session, $error) = get_snmp_session($hostname, $community);	# Open SNMP connection

### OIDs
### Source : BLACKBERRYSERVERMIB-SMIV2
my $RIMVERS = '.1.3.6.1.4.1.3530.5.1.0'; # RIM VERSION
my $INSTID = '.1.3.6.1.4.1.3530.5.20.1.1'; # BlackBerry Server instance number (1..n)
my $SRPCON = '1.3.6.1.4.1.3530.5.25.1.10.'; # Connection Status to SRP Router 
my $SRPLASTCON = '1.3.6.1.4.1.3530.5.25.1.11.'; # Last SRP Connect
my $BESVERS = '1.3.6.1.4.1.3530.5.20.1.10.'; # Version of BES
my $PENDINGMSG = '1.3.6.1.4.1.3530.5.25.1.25.'; # Number of messages pending
my $USEDLICENSES = '1.3.6.1.4.1.3530.5.20.1.21.'; # Number of used Licenses

## Checks
my $RIMVERSOID = get_snmp_value($session, $RIMVERS);
# switch module is better
if ( $RIMVERSOID >= 5 )
{
  for ("$query") {
	if (/srp-connect/) { ($state, $string) = check_srpconnect(); }
	elsif (/bes-version/) { ($state, $string) = check_besversion(); }
	elsif (/msg-pending/) { ($state, $string) = check_msgpending(); }
	elsif (/used-licenses/) { ($state, $string) = check_usedlicenses(); }
	else { $state = $ERRORS{'UNKNOWN'}; $string = "UNKNOWN: query not implemented. Use perl $PROGNAME --help"; }
  }
}
else
{
  $state = $ERRORS{'CRITICAL'};
  $string = "CRITICAL: BES Version " . $RIMVERSOID . " not supported by this plugin.";
}

# Just in case of problems, let's not hang Nagios
$SIG{'ALRM'} = sub {
	print "UNKNOWN - Plugin Timed out\n";
	exit $ERRORS{"UNKNOWN"};
};
alarm($TIMEOUT);

## Close SNMP connection
close_snmp_session($session);  

# exit with a return code matching the state...
print $string."\n";
exit($state);

########################################################################
##  Subroutines below here....
########################################################################
sub get_snmp_session{
	my $ip        = $_[0];
	my $community = $_[1];
	my ($session, $error) = Net::SNMP->session(
	-hostname  => $ip,
	-community => $community,
	-port      => $port,
	-timeout   => $timeout,
	-retries   => 3,
	-version	=> $protocol,
	-translate => [-timeticks => 0x0]
	);
	return ($session, $error);
} # end get snmp session

sub check_srpconnect{
# parse all instances
	my %snmp_instances = %{get_snmp_table($session, $INSTID)};
	my $SRPLASTOIDREADABLE;
	my $error = 0;
	while (($oid, $value) = each (%snmp_instances)) {
		my $SRPOID = get_snmp_value($session, $SRPCON.$value);
		my $SRPLASTOID = get_snmp_value($session, $SRPLASTCON.$value);
		$SRPLASTOIDREADABLE = localtime($SRPLASTOID);
		if ( $SRPOID <= 0 )
		{
			$error++;
		}
	}

	if ( $error == 0)
	{
		$string = "OK: Successful connected to SRP-Router. Last Connection: " . $SRPLASTOIDREADABLE . "";
		$state = $ERRORS{"OK"};
	}
	else
	{
		$string = "CRITICAL: Connection to SRP-Router failed.";
		$state = $ERRORS{"CRITICAL"};
	}
	return ($state, $string);
}

sub check_besversion{
	my %snmp_instances = %{get_snmp_table($session, $INSTID)};
	my $RESULTS;
	while (($oid, $value) = each (%snmp_instances)) {
		my $BESVOID = get_snmp_value($session, $BESVERS.$value);
		$RESULTS .= "#" . $value . ":" . $BESVOID. "/";
	}
	$string = "BlackBerry Enterprise Server Version: " . $RESULTS. "";
	$state = $ERRORS{"OK"};
	return ($state, $string);
}

sub check_msgpending{
	my %snmp_instances = %{get_snmp_table($session, $INSTID)};
	my $nb_crit = 0;
	my $nb_warn = 0;
	my $PENDINGMSGOID;
	my $RESULTS;
	while (($oid, $value) = each (%snmp_instances)) {
		$PENDINGMSGOID = get_snmp_value($session, $PENDINGMSG.$value);
		if ( $PENDINGMSGOID >= $crit )
		{
			$nb_crit++;
		}
		elsif ( $PENDINGMSGOID >= $warn )
		{
			$nb_warn++;
		}
		
		$RESULTS .= $value . ":" . $PENDINGMSGOID . "/";
	}

	if ( $nb_crit > 0 )
	{
		$string = "CRITICAL";
		$state = $ERRORS{"CRITICAL"};
	}
	elsif ( $nb_warn > 0 )
	{
		$string = "WARNING";
		$state = $ERRORS{"WARNING"};
	}
	elsif ( $nb_warn == 0 && $nb_crit == 0 )
	{
		$string = "OK";
		$state = $ERRORS{"OK"};
	}
	$string = $string . ": Pending Mails: $RESULTS|Pending=$warn;$crit;;";
	return ($state, $string);
}

sub check_usedlicenses{
	my %snmp_instances = %{get_snmp_table($session, $INSTID)};
	my $nb_crit = 0;
	my $nb_warn = 0;
	my $LICENSESOID;
	my $RESULTS;
	while (($oid, $value) = each (%snmp_instances)) {
		$LICENSESOID = get_snmp_value($session, $USEDLICENSES.$value);	
		if ( $LICENSESOID >= $crit )
		{
			$nb_crit++;
		}
		elsif ( $LICENSESOID >= $warn )
		{
			$nb_warn++;
		}
		$RESULTS .=  $value . ":" . $LICENSESOID . "/";
	}

	if ( $nb_crit > 0 )
	{
		$string = "CRITICAL";
		$state = $ERRORS{"CRITICAL"};
	}
	elsif ( $nb_warn > 0 )
	{
		$string = "WARNING";
		$state = $ERRORS{"WARNING"};
	}
	elsif ( $nb_warn == 0 && $nb_crit == 0 )
	{
		$string = "OK";
		$state = $ERRORS{"OK"};
	}
	$string = $string . ": Licences used: $RESULTS|Licences=$warn;$crit;;";
	$state = $ERRORS{"CRITICAL"};
	return ($state, $string);
}

sub close_snmp_session{
	my $session = $_[0];

	$session->close();
} # end close snmp session

sub get_snmp_value{
	my $session = $_[0];
	my $oid     = $_[1];
	my (%result) = %{get_snmp_request($session, $oid) or die ("SNMP service is not available on ".$hostname) }; 
	return $result{$oid};
} # end get snmp value

sub get_snmp_request{
	my $session = $_[0];
	my $oid     = $_[1];
	return $session->get_request($oid) || die ("SNMP service not responding");
} # end get snmp request

sub get_snmp_table{
	my $session = $_[0];
	my $oid     = $_[1];
	return $session->get_table(	
	-baseoid =>$oid
	); 
} # end get snmp table


sub parse_args
{
	my $hostname = "127.0.0.1";
	my $community = "public";
	my $port = 161;
	my $protocol = 1;
	my $timeout = 10;
	my $query = "";
	my $warn = 5;
	my $crit = 20;

	pod2usage(-message => "UNKNOWN: No Arguments given", -exitval => $ERRORS{'UNKNOWN'}, -verbose => 0) if ( !@ARGV );

	Getopt::Long::Configure('bundling');
	GetOptions(
	'hostname|H=s'	=> \$hostname,
	'query|Q=s'	=> \$query,
	'community|C:s' => \$community,
	'timeout|T:i'	=> \$timeout,
	'warning|w:i'	=> \$warn,
	'critical|c:i'	=> \$crit,
	'port|p:i'	=> \$port,
	'protocol|P:i'	=> \$protocol,
	'version|V'	=> \$version,
	'help|h'	=> \$help,
	) or pod2usage(-exitval => $ERRORS{'UNKNOWN'}, -verbose => 0);

	pod2usage(-exitval => $ERRORS{'UNKNOWN'}, -verbose => 2) if $help;
	print ("$PROGNAME : $VERSION\n"); exit  if $version;
	return ($hostname, $community, $port, $protocol, $timeout, $query, $warn, $crit);
}		

__END__

=head1 NAME

Check BlackBerry Enterprise Server 5

=head1 SYNOPSIS

=item S<check_bes5.pl -Q <query> [-H <hostname> -C <COMMUNITY> -T <timeout>] [-p <port>] [-P <snmp-version>] [-w <INTEGER>] [-c <INTEGER>]>

Options :

-H --hostname	Host name or IP Address (default is 127.0.0.1)
-Q --query	the part to query:
srp-connect = SRP connection status
bes-version = BlackBerry Enterprise Server Version
msg-pending = Number of messages pending
used-licenses = Number of used Licenses
-C --community	Optional community string for SNMP communication (default is "public")
-p --port	Port number (default: 161)
-P, --protocol	SNMP protocol version [1,2c] (SNMP Version 3 is not supported yet)
-w --warning	Warning Threshold
-c --critical	Critical Threshold
-h --help	Print detailed help screen
-V --version	Print version information

=head1 OPTIONS

=over 8

=item B<-H|--host>

STRING or IPADDRESS - Check interface on the indicated host.

=item B<-C|--community>

STRING - Community-String for SNMP

=item B<-Q|--query>

STRING - srp-connect, bes-version, msg-pending, used-licenses

=item B<-p|--port>

INTEGER - Pourt Number 

=item B<-P|--protocol>

INTEGER - SNMP Protocol version

=item B<-w|--warning>

INTEGER - Warning threshold, applies to msg-pending, used-licenses

=item B<-c|--critical>

INTEGER - Critical threshold, applies to msg-pending, used-licenses 

=back

=head1 DESCRIPTION

This plugin checks BlackBerry Enterprise Server 5 via SNMP 

=cut

# EOF
