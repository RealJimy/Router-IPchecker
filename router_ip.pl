#!/usr/bin/perl

use Modern::Perl;
use File::Basename;
use Net::Telnet;
use Socket;

our $log_path =  dirname(__FILE__) . '/logs';

my $routerAccess = {
    'IP' => '192.168.1.1',
    'Login'  => 'user',
    'Pass'   => 'pass',
    'prompt' => '/\(config\)\>/',
};

my $priorityRange = 99;
my $problems      = 0;

# interfaces: values = minimal priorities, maximal priority = minimal + $priorityRange
my %interfaces = ( 'PPPoE0' => 200, 'PPPoE1' => 100 );

foreach my $ifaceName ( keys %interfaces ) {
    my ( $params, $errors ) = &checkConnection( $ifaceName, $routerAccess );
    while ($errors) {
        $problems = 1;
        &logger(@$errors);
        ( $params, $errors ) = &changePriority(
            $ifaceName,
            $routerAccess,
            &randomPriority(
                $params->{'priority'} ? $params->{'priority'} : 0,
                $interfaces{$ifaceName},
                $priorityRange
            )
        );
    }
}

&logger() unless $problems;

# change priority for internet connection
sub changePriority() {
    my ( $ifaceName, $connectionParams, $newPriority ) = @_;

    my $telnet = &telnetConnection($connectionParams);
    my @lines  = $telnet->cmd(
        String => 'interface ' . $ifaceName . ' ip global ' . $newPriority,
        Prompt => $connectionParams->{'prompt'}
    );
    $telnet->close;
    &logger( $ifaceName . ' - changed priority to ' . $newPriority );
    sleep(20);
    return &checkConnection( $ifaceName, $connectionParams );
}

sub randomPriority() {
    my ( $current, $minimal, $maxRange ) = @_;

    my $rand = int( rand($maxRange) ) + $minimal;
    while ( $rand == $current ) {
        $rand = int( rand($maxRange) ) + $minimal;
    }
    return $rand;
}

sub checkConnection() {
    my ( $ifaceName, $connectParams ) = @_;

    my @errors;
    my %privateIPranges = (
        '167772160'  => 184549375,  # 10.0.0.0 - 10.255.255.255
        '2130706432' => 2147483647, # 127.0.0.0 - 127.255.255.255
        '2886729728' => 2887778303, # 172.16.0.0 - 172.31.255.255
        '3232235520' => 3232301055, # 192.168.0.0 - 192.168.255.255
    );

    my $telnet = &telnetConnection($connectParams);
    my @lines  = $telnet->cmd(
        String => 'show interface ' . $ifaceName,
        Prompt => $connectParams->{'prompt'}
    );
    $telnet->close;

    if ( !scalar(@lines) ) {
        push @errors, $ifaceName . ' - empty response ';
        return ( undef, \@errors );
    }

    my %params;
    foreach my $line (@lines) {
        $line =~ s/^\s*|\s*$//g;
        print $line . "\n";
        my ( $name, $value ) = split( /:\s+/, $line );
        if ($name) {
            $params{$name} = $value;
        }
    }

    if (   $params{'link'} eq 'up'
        && $params{'state'} eq 'up'
        && $params{'connected'} eq 'yes' )
    {
        if (   $params{'priority'} < $interfaces{$ifaceName}
            || $params{'priority'} > $interfaces{$ifaceName} + $priorityRange )
        {
            push @errors,
              $ifaceName . ' has wrong priority ' . $params{'priority'};

        }
        elsif ( $params{'defaultgw'} eq 'yes' ) {    #   active
            my $publicIP = &getMyIp(1);
            if ( $params{'address'} ne $publicIP ) {
                push @errors,
                    $ifaceName . ' IP '
                  . $params{'address'}
                  . ' is not equal public IP '
                  . $publicIP
                  . '; [remote: '
                  . $params{'remote'} . ']';
            }

        }
        else {    #   not active at the moment, check by private ip ranges
            my $intIP = unpack "N", inet_aton( $params{'address'} );
            foreach my $start ( keys %privateIPranges ) {
                if (   $intIP >= int($start)
                    && $intIP <= $privateIPranges{$start} )
                {
                    push @errors,
                        $ifaceName . ' IP '
                      . $params{'address'}
                      . ' is in private range and not active; [remote: '
                      . $params{'remote'} . ']';
                    last;
                }
            }
        }
    }
    else {    #   disconected
        &logger($ifaceName
              . ' - disconnected [link:'
              . $params{'link'}
              . ';state:'
              . $params{'state'}
              . ';connected:'
              . $params{'connected'}
              . ']' );
    }

    return ( \%params, scalar(@errors) ? \@errors : undef );
}

sub logger() {
    my @logTime = localtime();

    our $log_path;
    open(
        my $flog,
        '>>',
        $log_path . '/router_IP_check_'
          . ( $logTime[5] + 1900 )
          . sprintf( "%02d", $logTime[4] + 1 ) . '.log'
    ) or die $!;
    if ( scalar(@_) ) {
        print $flog map "\n" . $_ . ' ' . &currentTimeStamp(), @_;
    }
    else {
        print $flog '.';
    }
    close $flog;
}

sub currentTimeStamp() {
    my @arrTime = localtime();
    return
        $arrTime[2] . ':'
      . $arrTime[1] . ':'
      . $arrTime[0] . ' '
      . $arrTime[3] . '/'
      . ( $arrTime[4] + 1 );
}

sub telnetConnection() {
    my ($params) = @_;

    my $telnet = new Net::Telnet( Timeout => 30 );
    $telnet->open( $params->{'IP'} );
    $telnet->waitfor('/Login:/');
    $telnet->print( $params->{'Login'} );
    $telnet->waitfor('/Password:/');
    $telnet->print( $params->{'Pass'} );
    $telnet->waitfor( $params->{'prompt'} );
    return $telnet;
}

sub getMyIp {
    my ($force) = @_;

    our $myIP;
    if ( !$myIP || $force ) {
        $myIP = `wget -qO- https://api.ipify.org`;
        chomp $myIP;
        if ( $myIP !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/ ) {
            print "\n" . ( 'Couldn\'t get current IP: ' . $myIP ) . "\n";
            exit;
        }

    }
    return $myIP;
}

