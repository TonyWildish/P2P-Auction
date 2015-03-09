package PSP::Util;
use strict;
use warnings;
use POSIX;
use POE;

use Data::Dumper;
$Data::Dumper::Terse=1;
$Data::Dumper::Indent=0;

sub Log { my $self=shift; print timestamp(), ' ', $self->{Me}, ': ', @_, "\n"; }
sub Dbg { my $self=shift; $self->Log(@_) if $self->{Debug}; }

sub daemon {
  my ($self, $me) = @_;
  my $pid;

  # Open the pid file.
  open(PIDFILE, "> $self->{Pidfile}")
      || die "$me: fatal error: cannot write to PID file ($self->{Pidfile}): $!\n";
  $me = $self->{Me} unless $me;

  return if $self->{Nodaemom};

  # Fork once to go to background
  die "failed to fork into background: $!\n"
      if ! defined ($pid = fork());
  close STDERR if $pid; # Hack to suppress misleading POE kernel warning
  exit(0) if $pid;

  # Make a new session
  die "failed to set session id: $!\n"
      if ! defined setsid();

  # Fork another time to avoid reacquiring a controlling terminal
  die "failed to fork into background: $!\n"
      if ! defined ($pid = fork());
  close STDERR if $pid; # Hack to suppress misleading POE kernel warning
  exit(0) if $pid;

  # Write our pid to the pid file while we still have the output.
  ((print PIDFILE "$$\n") && close(PIDFILE))
      or die "$me: fatal error: cannot write to $self->{Pidfile}: $!\n";

  print "writing logfile to $self->{Log}\n";
  # Close/redirect file descriptors
  $self->{Log} = "/dev/null" if ! defined $self->{Log};
  open (STDOUT, ">> $self->{Log}")
      or die "$me: cannot redirect output to $self->{Log}: $!\n";
  open (STDERR, ">&STDOUT")
      or die "Can't dup STDOUT: $!";
  open (STDIN, "</dev/null");
  $|=1; # Flush output line-by-line
}

sub ReadConfig {
  my ($this,$hash,$file) = @_;

  $file = $this->{Config} unless $file;
  defined($hash) or die "No named item from config file for $this->{Me}\n";
  defined($file) && -f $file or die "No config file for $this->{Me}\n";
 
  $this->Log("Reading '$hash' entry from $file");
  eval {
    do "$file";
  };
  if ( $@ ) {
    die "ReadConfig: $file: $@\n";
    return;
  }

  no strict 'refs';
  my $nkeys = scalar keys %$hash;
  if ( ! $nkeys ) { die "No '$hash' field in $file!\n"; }
  map { $this->{$_} = $hash->{$_} } keys %$hash;
  undef %$hash;
}

sub timestamp {
  my ($year,$month,$day,$hour,$minute,$seconds) = @_;

  my @n = localtime;

  defined($year)    or $year    = $n[5] + 1900;
  defined($month)   or $month   = $n[4] + 1;
  defined($day)     or $day     = $n[3];
  defined($hour)    or $hour    = $n[2];
  defined($minute)  or $minute  = $n[1];
  defined($seconds) or $seconds = $n[0];

  sprintf("%04d%02d%02d-%02d:%02d:%02d",
          $year,$month,$day,$hour,$minute,$seconds);
}

sub min {
  my ($x,$y) = @_;
  return $x if $x < $y;
  return $y;
}

# POE session states
sub _child {}
sub _stop {}
sub _default {
  my ( $self, $kernel, $args ) = @_[ OBJECT, KERNEL, ARG1 ];
  my $ref = ref($self);
  if ( defined($args) ) {
    $args = Dumper($args)
  } else {
    $args = '(null)';
  }
  die <<EOF;

  Default handler for class $ref:
  The default handler caught an unhandled "$_[ARG0]" event.
  The $_[ARG0] event was given these parameters: $args

  (...end of dump)
EOF
}

sub _start {
  my ( $self, $kernel, $session ) = @_[ OBJECT, KERNEL, SESSION ];
  $kernel->alias_set($self->{Me});
  $self->Log("Alias set to ",$self->{Me});
  if ( $self->can('start') ) { $self->start(); }
  if ( $self->can('PostReadConfig') ) { $self->PostReadConfig(); }
  $kernel->state($_, $self) foreach @{$self->{HandlerNames}};
}

sub ddie {
  my ($self,$msg,$var) = @_;
  print Dumper($var),"\n";
  die $self->{Me},': ',$msg,"\n\n";
}

1;
