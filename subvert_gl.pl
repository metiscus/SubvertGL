#!/usr/bin/perl -w
# GPLV3
###############################################################################
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
###############################################################################
#
#	subvert_gl.pl - Utility to debug OpenGL calls on hard to debug systems
#	Michael A Bosse (metiscus@gmail.com) <michaelabosse.com>
#
#	Version 1.0 - First Public Release
#

use warnings;
use strict;

sub PreprocessSource {
	# use the c preprocessor to remove inline comments and clean up syntax
	return `gcc -fpreprocessed -dD -E $_[0]`;
}

sub GatherTypedefs {
	# get the list of typedef types from the file
	my $fileText = $_[0];
	my @types = ($fileText =~ /typedef (.*) (GL[a-z]*);/g);
	#print join(", ", @types);
	return @types
}

sub GatherFunctionInfo {
	# get a list of functions out of the file along with types and parameters
	# ex: GLAPI void GLAPIENTRY glColor3bv( const GLbyte *v );
	# equals: void, glColor3Bv, (, const GLbyte *v, );,
	my $fileText = $_[0];
	my @functions = ($fileText =~ /GLAPI (.*) GLAPIENTRY (.*)(\() (.*) (\);)/g);
	#print join(", ", @functions);
	return @functions;
}

sub GatherFunctionNames {
	# get a list of function names from function info
	my @functionNames = ();
	my $last;
	foreach(@_) {
		if ( $_ eq '(' ) {
			push(@functionNames, $last);
		}
		else {
			$last = $_;	
		}		
	}
	#print join(", ", @functionNames);
	return @functionNames;
}

sub GenerateFunctionPtrTypedefs {
	# generates typedefs for function pointers for the passed in functions
	my $functionPointers = "";
	
	my $isBegin = 1;
	foreach(@_) {
		if ( $isBegin == 1) {
			$functionPointers .= ('typedef ' . $_ . '(*_');
			$isBegin = 0;
		}
		elsif ( $_ eq '(') { # check for begin of args
			$functionPointers .= (')' . $_);
		}	
		elsif ( $_ eq ');') { # check for end of args
			$isBegin = 1;
			$functionPointers .= ($_ . "\n");
		}
		else { 
			$functionPointers .= $_;
		}
	}
	
	#print $functionPointers;
	return $functionPointers;
}

sub GenerateFunctionPtrDecls {
	# generates function pointer declarations for the passed list of functions
	my $functionPointerDecls = "";
	
	foreach(@_) {
		$functionPointerDecls .= "static _$_ my$_ = NULL;\n";
	}
	
	#print $functionPointerDecls;
	return $functionPointerDecls;
}

sub GenerateFunctionPtrInits {
	# generates statements to look up original functions using the first parameter
	my $ptr = $_[0];
	
	my $functionPointerInits = "";
	
	foreach(@{$_[1]}) {
		$functionPointerInits .= "\t\tif( ( my$_ = dlsym($ptr, \"$_\") ) == NULL ) { fprintf( stderr, \"dlsym() error '%s'\\n\", dlerror() ); /*exit(1);*/ }\n";
	}
	
	#print $functionPointerInits;
	return $functionPointerInits;
}

sub GenerateStubFunctions {
	# generates stub functions to call the real function via the function pointer to allow hooking
	
	my $stubFunctions = "";
	my $isArgs = 0;
	my $argCount = 0;
	my $functionName = "";
	my @argTypes = ();
	my @argNames = ();
	my @argExtra = ();
	
	foreach(@_) {
		if ( $_ eq '(') {
			$isArgs = 1;
			$argCount = 0;
			$stubFunctions .= $_;
		}	
		elsif ( $_ eq ');') { 
			# strip comma
			chop($stubFunctions);
			
			$isArgs = 0;
			
			$stubFunctions .= ") {\n" .
			"\tfprintf(stderr,\" $functionName( ";
			# convert types to parameters
			#begin gl.h hard code
			my $argId = 0;
			my $argStr = "";
			foreach(@argTypes) {
				my $argument = $_;
				if (!( $argument =~ /.*\*/ ) && ( $argExtra[$argId] eq '' )) {
					$argStr .= "(double)$argNames[$argId],";
					$stubFunctions .= "%f, ";
				}
				$argId++;
			}
			#end gl.h hard code
			
			chop($argStr);
			if ( $argStr ne '' ) {
				chop($stubFunctions);
				$stubFunctions .= ")\\n\",";
			}
			else
			{
				$stubFunctions .= ")\\n\"";
			}
			
			
			$stubFunctions .= $argStr . ");\n".
			"\tmb$functionName(" .
			join(", ", @argNames) . ");\n" .
			"}\n";
			
			# reset these arrays for the next function
			@argTypes = ();
			@argNames = ();
			@argExtra = ();
		}
		elsif ( $isArgs == 1 )
		{
			#write the code for an argument and extract information about the arguments
			$stubFunctions .= "$_,";
			$argCount++;
			
			#this code splits the argument into a type and a name ( unless it is void )
			my $args = $_;
			chomp($args);
			if ( $args eq 'void' ) {
				# void functions don't need any work done for them
			}
			else {
				# the line comes in with all arguments, process each individually
				my @tokens = split(',', $_);
				foreach(@tokens) {
					# for each token, extract the type and the name
					my $token = $_;
					chomp($token);
					my @type = ($token =~ /(.* +\**).*/);
					my @name = ($token =~ /.* +\**(.*)/);
					my @array = ($name[0] =~ /([A-Za-z0-9_]+)(\[.*\])*/);
					#print ">>>>$token<<<<\n$functionName() type: $type[0] name: $array[0]\n";
					push(@argTypes, $type[0]);
					push(@argNames, $array[0]);
					if ( defined($array[1])) {
						push(@argExtra, $array[1]);	
					}
					else {
						push(@argExtra, '');
					}
				}
			}
		}
		else {
			#it is random other text, write it out
			$stubFunctions .= "$_ ";
			$functionName = $_;
		}
	}
	
	#print $stubFunctions;
	return $stubFunctions;
}

sub GenerateTypedefs {
	# build the typedefs
	my $i = 0;
	my $typeDefs = '';
	foreach(@{$_[0]}) {
		if ( $i == 0 ) {
			$i = 1;
			$typeDefs .= "typedef $_ ";
		}
		else {
			$i = 0;
			$typeDefs .= "$_;\n";
		}
	}
	
	return $typeDefs;
}

#code goes here to generate the file
my $fileText     = PreprocessSource('/usr/include/GL/gl.h');
my @typeDefs     = GatherTypedefs( $fileText );
my @funcInfo     = GatherFunctionInfo( $fileText );
my @funcNames    = GatherFunctionNames( @funcInfo );
my $funcPtrTypes = GenerateFunctionPtrTypedefs( @funcInfo );
my $funcPtrDecls = GenerateFunctionPtrDecls( @funcNames );
my $funcPtrInits = GenerateFunctionPtrInits( "g_mb_ptr", \@funcNames );
my $funcStubs    = GenerateStubFunctions( @funcInfo );
my $fileTypedefs = GenerateTypedefs( \@typeDefs );

open( my $outc, '>', "gloverride.c" ) or die "Cannot open gloverride.c exiting.";

# Output of program is LGPLv3
print $outc <<OUT
/*
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published
	by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// this is included but it may not be needed if you use the built in typedef generation
#include <GL/gl.h>

/* OpenGL typedefs from GL/gl.h */
$fileTypedefs

/* Function pointer typedefs */
$funcPtrTypes

/* Function pointer declarations */
$funcPtrDecls

/* Initialization */
void* g_mb_ptr = NULL;
void mb_init_gl()
{
	fprintf(stderr, "...Loading GL Hacks...");
	g_mb_ptr = dlopen("/usr/lib64/libGL.so", RTLD_LOCAL | RTLD_LAZY | RTLD_DEEPBIND);
	if (!g_mb_ptr)
	{ 
		fprintf(stderr, "%s\\n", dlerror());
		exit(1);
	} else {
$funcPtrInits
	}
}

/* Function stubs */
$funcStubs


OUT
;