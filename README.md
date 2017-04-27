UKTM_regression_test: Regression testing UK TIMES dd files generated using Veda FE
===================================================================================

This Ruby script allows you to compare 2 directories' worth of DD (text) files. It uploads each file to a temporary table on a postgres database and then compares the entries in each of these tables. The match is on input dd filename and the contents of the line entry from that file: in effect it assumes there are no duplicate lines within a dd. Outputs are CSVs of summary counts / percentages of file entries the same / different by input file, and a separate file containing those differences together with the line number of the file from which they came.

Run the script using the following syntax:

    ruby <"full path to script"> <"full path to first folder of dds"> <"full path to second folder of dds"> ["optional full path to where output CSVs should go"]
    
Output CSVs go to the second folder of dds if no other location is specified.

Input folder names are used as column headings in some of the database temporary tables. There is some replacement of characters which are illegal in unquoted Postgres field names (i.e. changes "." and "-" to underscores). However, there is no checking of or dealing with spaces in folder names so don't include any!

Note that requires Ruby gem 'pg', the Postgres driver for Ruby. There is some code to try to install this if it's missing, but this may not work if you have more than one Ruby installation on the machine. (In which case install by hand.)
