#!/usr/bin/perl

package CA::ContentAddressable;

use Digest::MD5;
use File::Find;

%CA::ContentAddressable::full_relationship_hash_map = (); # Holds hash of filename and objects of its children(filename -> [obj of ref])
%CA::ContentAddressable::md5_hash = (); # Holds hash of filename and md5 of filename (Cumulative md5)
%CA::ContentAddressable::content_name_hash_map =(); # Holds hash of filename and its content_Addressable_name
$CA::ContentAddressable::rootDir = "<file_path>";
$CA::ContentAddressable::tempBackupFile  = "<file_path>";
$CA::ContentAddressable::nonexistant  = 0;
$CA::ContentAddressable::converted    = 0;
$CA::ContentAddressable::totalchanges = 0;
$CA::ContentAddressable::totalCA = 0;
$CA::ContentAddressable::totalappCA = 0;
# Constructor
sub new {
	my $class = shift;
	my $self  = {
		filename => shift,
		md5      => shift
	};
	bless $self, $class;
	return $self;
}

# gets the filename of the object referring
sub getFile {
	my ($self) = @_;
	return $self->{filename};
}

# gets md5 of the object referring
sub getMd5 {
	my ($self) = @_;
	return $self->{md5};
}

# Calculates md5 of a file
sub md5Sum {
	my $file = shift;

	my $md5 = Digest::MD5->new;
	open( FILE, $file ) or return;
	$md5->addfile(FILE);
	my $hexDigest = $md5->hexdigest;
	close(FILE);
	return $hexDigest;
}

# constructs a hash of all the referenced files in a file.
sub extract_files {
	my ($filename) = @_;

	#print "extract :  ".$filename."\n";
	open( FILE, "<$filename" ) or return;
	my @children = ();
	my %temp     = ();   # to avoid duplicate references.
	while (<FILE>) {
		my $ref = /\s*"\%CA{'([^']+)'}"/;
		if ($ref) {
			$CA::ContentAddressable::totalCA+=$ref;
			push @children, $CA::ContentAddressable::rootDir . $1
			  if ( ( $1 !~ /^\s*$/ ) and not defined $temp{$1} );
			$temp{$1} = 1;
		}
	}
	#	print "\n".Data::Dumper::Dumper(@children)."\n";
	close(FILE);
	return @children;
}

sub build_hash_map {
	CA::ContentAddressable::build_map($File::Find::name);
}

# Constructs a hash map of all files to the object of its children.
sub build_map {
	my ($filename) = @_;

	/.svn/ and $File::Find::prune = 1;
	return if ( -d $filename );

	#	print "\n$filename ==>\n";
	return @{ $CA::ContentAddressable::full_relationship_hash_map{$filename} }
	  if defined $CA::ContentAddressable::full_relationship_hash_map{$filename};

	my $obj = new CA::ContentAddressable( $filename, md5Sum($filename) );

	push @{ $CA::ContentAddressable::full_relationship_hash_map{$filename} }, $obj;

	my @children = extract_files($filename);

	# Adding children
	foreach (@children) {
		my $child_filename = $_;
		my @arr            = build_map($child_filename);
		foreach my $child_obj (@arr) {
			my $duplicate = 0;  # To avoid duplicate children references.
			foreach
			  my $parent_obj ( @{ $CA::ContentAddressable::full_relationship_hash_map{$filename} } )
			{
				if ( $parent_obj eq $child_obj ) {
					$duplicate = 1;
					last;
				}
			}
			push @{ $CA::ContentAddressable::full_relationship_hash_map{$filename} }, $child_obj
			  if $duplicate ne 1;
		}
	}
	return @{ $CA::ContentAddressable::full_relationship_hash_map{$filename} };
}

# gets the reference to the hash map of filename -> objects of its children
sub get_hash_map {
	return \%CA::ContentAddressable::full_relationship_hash_map if keys(%CA::ContentAddressable::full_relationship_hash_map);
}

# calculates Content addressable names based on md5.
sub compute_addressable_names {
	my $hash_map = shift;
	my $str      = "";
	my $md5 = Digest::MD5->new;
	while ( my ( $k, $v ) = each %$hash_map ) {
		foreach (@$v) {
			if ( not defined $_->getMd5() ) {
				$CA::ContentAddressable::md5_hash{$k} = undef;
				next;
			}
			$str .= $_->getMd5();
		}
	#	print "$k ===> $str";
	#	print "\n";
		next if $str eq "";
		if ( scalar(@$v) eq 1 ) {
			$CA::ContentAddressable::md5_hash{$k} = $str;		
		}
		else {
			$md5->add($str);
			my $digest = $md5->hexdigest;
			$CA::ContentAddressable::md5_hash{$k} = $digest;
		}
		$str = "";
	}
	return \%CA::ContentAddressable::md5_hash
	  if keys(%CA::ContentAddressable::md5_hash);
}

sub expand_tags_in_md5dir {
	CA::ContentAddressable::expand_tags($File::Find::name);
}

# Creates MD5 Directory Structure.
sub create_md5_dir {
	my $content_addressable_hash_map = shift;
	mkdir $CA::ContentAddressable::rootDir ."/md5";
	while ( my ( $file_path, $md5 ) = each %$content_addressable_hash_map ) {
		if ( not defined $md5) {
			my @filepath_split_array        = split( $CA::ContentAddressable::rootDir, $file_path );
			$CA::ContentAddressable::content_name_hash_map{$file_path} = $filepath_split_array[1];
		   #print "file : $file_path doesnot exist!!\n";
			$CA::ContentAddressable::nonexistant+= 1 ;
			next;
		}
		my @arr        = split( '/', $file_path );
		my $filename   = $arr[-1];
		my $sub_folder =  "/md5/".substr( $md5, 0, 2 )."/";
		my $content_addressable_file_name =
		    $CA::ContentAddressable::rootDir
		  . $sub_folder
		  . $md5 . "_"
		  . $filename;
		  
		print $file_path."\n".$content_addressable_file_name. "\n";

		$CA::ContentAddressable::content_name_hash_map{$file_path} =
		  $sub_folder. $md5 . "_" . $filename;

		#creating md5 files and directories
		mkdir $CA::ContentAddressable::rootDir ."/md5/" . substr( $md5, 0, 2 );

	   `cp '$file_path' '$content_addressable_file_name'`;	
	   $CA::ContentAddressable::converted+=1;
	}
}

# Expands %CA tags.
sub expand_tags {
	my ($filename) = @_;
	
	/.svn/ and $File::Find::prune = 1;
	
	return if ( -d $filename );
	return if ( -B $filename );
	
	my $backup_filename = $CA::ContentAddressable::tempBackupFile;
	
	open( FILE_ACTUAL, "<$filename" ) or die "Expand Error";
	my $CA_file = $CA::ContentAddressable::rootDir.$CA::ContentAddressable::content_name_hash_map{$filename} 
	  if defined $CA::ContentAddressable::content_name_hash_map{$filename} ;
	open( CA_FILE, ">$CA_file" )
	  if defined $CA::ContentAddressable::content_name_hash_map{$filename}
		  or return; 
	open BACKUP, ">$backup_filename"  or die "Cannot open backup file: $!";

	while (<FILE_ACTUAL>) {
	   my $count = s/\s*"\%CA{'([^']+)'}"/"$CA::ContentAddressable::content_name_hash_map{$CA::ContentAddressable::rootDir.$1}"/g;
	   $CA::ContentAddressable::totalchanges+=$count if $count > 0;
	   print CA_FILE $_;
	   print BACKUP $_;
	}
	$CA::ContentAddressable::converted+=1;
	rename $backup_filename, $filename;
	close(FILE_ACTUAL);
	close(CA_FILE);
}

# Expand AppServer Directory %CA tags.
sub expandAppServerDir {
	my $filename = $File::Find::name;
	
	/.svn/ and $File::Find::prune = 1;
	return if ( -d $filename );
	my $backup_filename = $CA::ContentAddressable::tempBackupFile;
#	print $File::Find::dir."\n";
	open FILE, $filename or die "Cannot open $filename: $!";
	open BACKUP, ">$backup_filename"
	  or die "Cannot open backup file: $!";
	  while (<FILE>) {
		my $count = s/\s*"\%CA{'([^']+)'}"/ "$CA::ContentAddressable::content_name_hash_map{$CA::ContentAddressable::rootDir.$1}" /g;
	  	if ((not defined $CA::ContentAddressable::content_name_hash_map{$CA::ContentAddressable::rootDir.$1} 
	  	       or  "" eq $CA::ContentAddressable::content_name_hash_map{$CA::ContentAddressable::rootDir.$1})) {
	  		$count = 0;
	  		my $temp = $1;
	  		$count = s/[\s]*""[\s]*/ "$temp" /g;
	  	} 
	  
	   $CA::ContentAddressable::totalappCA+=$count if $count > 0;
	   $CA::ContentAddressable::totalchanges+=$count if $count > 0;
	   print BACKUP $_;
	  }
	   $CA::ContentAddressable::converted+=1 if $count > 0;
    rename $backup_filename, $filename;
	close BACKUP;
	close FILE;
}


sub removeBackUpDir {
	`rmdir "/home/nsairam/Desktop/backup"` or return;
}

# Invoke This !! 
# Required : App-Root Directory
# Steps involved : get the root directory, build full-relationship map, compute contentAddressable names, 
# create ContentAddressable directories, Expand '%CA{}' tags in both app & web root dirs.

sub computeContentAddressable {
	my ($CA_app_Dir) = shift;
	my ($dir) = $CA::ContentAddressable::rootDir;
	find( { wanted => \&build_hash_map }, "$dir" );
	my $full_relationship_hash_map = CA::ContentAddressable::get_hash_map();

#	print "\n" . Data::Dumper::Dumper($full_relationship_hash_map) . "\n";

	my $content_addressable_names_hash =
 	 CA::ContentAddressable::compute_addressable_names($full_relationship_hash_map);

 #   print "\n" . Data::Dumper::Dumper($content_addressable_names_hash) . "\n";

    CA::ContentAddressable::create_md5_dir($content_addressable_names_hash);
    find( { wanted => \&expand_tags_in_md5dir }, "$dir" );
 #   print "\n" . Data::Dumper::Dumper(%content_name_hash_map) . "\n";

	# APP DIRECTORY
 	mkdir "/home/nsairam/Desktop/backup";
	find( { wanted => \&expandAppServerDir }, $CA_app_Dir );
	removeBackUpDir();
}

1;
