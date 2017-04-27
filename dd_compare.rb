
require 'pathname'
require 'fileutils'
require 'ostruct'
require 'optparse'
require 'thwait'
require 'logger'

#following checks the postgres driver is installed and installs it if not. It assumes that there's only one Ruby installation on the machine
#If there are more, it might try to install the gem to the wrong ruby version which will cause the code to fail
begin
  require 'pg'
rescue LoadError
  system('gem install pg')
  require 'pg'
end

#this function loads each set of dd files to its respective temp table on the database
#includes the source directory name & source file name and line no.
def load_dds(dir_path, pg_connection, tablename)
  Dir.glob(dir_path + '/*.dd') do |dd_file|
#i.e. for each dd file... Open it    
  fin = File.new(dd_file, "r")
  i=0
#Get just the directory name, not the path to it.    
  dirname = File.dirname(fin).gsub(/^(.+)\//,"")
#Get rid of at least _some_ characters which are not allowed in postgres field headings  
  dirname=dirname.gsub(/[-\.]/,"_")
#Get just the file name, not the path to id
#NB File assumes unix path separators (='/', hence need for simple gsub, or use require 'pathname'...)         
    fn=dd_file.gsub(/^(.+)\//,"")
    while (line = fin.gets)
      i+=1
#chomp removes newline characters which gets adds.      
      res  = pg_connection.exec('insert into '+tablename+' select $1,$2,$3,$4',[dirname,fn,i.to_s,line.chomp])
    end
  end  
end
#The following needs to match your postgres configuration... database name can be any   
conn = PGconn.connect( "host=localhost port=5432 dbname=postgres user=postgres")

#First argument to the script is the "old" dd files, 2nd is the "new" dd files. These must not have spaces in them
oldpath = ARGV[0].gsub("\\","/")
newpath = ARGV[1].gsub("\\","/")

#Create the temp tables on postgres
conn.exec('drop table IF exists regold') 
conn.exec('create temp table regold(sourcef varchar, filename varchar,lineno varchar,entry varchar)') 
conn.exec('drop table IF exists regnew')
conn.exec('create temp table regnew(sourcef varchar, filename varchar,lineno varchar,entry varchar)') 

#Load the dds using the above function
load_dds(oldpath,conn, "regold")
load_dds(newpath,conn,"regnew")

#The 3rd argument to the script is optional. It's the directory path where you want the output CSVs to go. If it's
#not included, CSVs will be sent to directory with the "new" dds in it. 
if ARGV.length==3
  outdir=ARGV[2].gsub("\\","/")
else
  outdir=newpath
end

s= "select * into temp basic_counts from   
  (  
    select a.filename filename, 'same' as entry, count(*) as counts from regold a inner join regnew b on a.filename=b.filename and a.entry=b.entry group by a.filename union  
    select a.filename, 'only_$1', count(*)  from regold a left join regnew b on a.filename=b.filename and a.entry=b.entry where b.filename is null group by a.filename union  
    select b.filename, 'only_$2', count(*)  from regold a right join regnew b on a.filename=b.filename and a.entry=b.entry where a.filename is null group by b.filename
  ) c;  
select * into temp summ_ind from
(
  select filename 
    ,sum(case when entry='same' then counts else 0 end) same 
    ,sum(case when entry='only_$1' then counts else 0 end) only_$1 
    ,sum(case when entry='only_$2' then counts else 0 end) only_$2 
    ,round(sum(case when entry='same' then counts else 0 end)::numeric/sum(counts)::numeric*100.0,1) same_percent 
    ,round(sum(case when entry='only_$1' then counts else 0 end)::numeric/sum(counts)::numeric*100.0,1) only_$1_percent 
    ,round(sum(case when entry='only_$2' then counts else 0 end)::numeric/sum(counts)::numeric*100.0,1) only_$2_percent 
  from basic_counts 
  group by filename
  order by same_percent
) a;
insert into summ_ind
  select 'all dds' 
    ,sum(case when entry='same' then counts else 0 end) same 
    ,sum(case when entry='only_$1' then counts else 0 end) only_$1 
    ,sum(case when entry='only_$2' then counts else 0 end) only_$2 
    ,round(sum(case when entry='same' then counts else 0 end)::numeric/sum(counts)::numeric*100.0,1) same_percent 
    ,round(sum(case when entry='only_$1' then counts else 0 end)::numeric/sum(counts)::numeric*100.0,1) only_$1_percent 
    ,round(sum(case when entry='only_$2' then counts else 0 end)::numeric/sum(counts)::numeric*100.0,1) only_$2_percent 
  from basic_counts; 
"
#Bit of a hack to substitute the actual directory names into the SQL. Use of $1, $2 above just gives something unique to search and replace
oldpath=oldpath.gsub(/[-\.]/,"_")
s=s.gsub('$1',oldpath.gsub(/^(.+)\//,""))
newpath=newpath.gsub(/[-\.]/,"_")  
s=s.gsub('$2',newpath.gsub(/^(.+)\//,""))
conn.exec(s)

#Actually run the comparison and generate the summary counts of same and different
s="
Copy (
  select * from summ_ind
) TO '"+outdir+"/summaryCnts.csv' delimiter ',' CSV HEADER;" 
conn.exec(s)
#Generate the list of differences between the files
s="
copy ( 
  select a.sourcef,a.filename,a.lineno,a.entry from regold a left join regnew b on a.filename=b.filename and a.entry=b.entry where b.entry is null  
  union   
  select b.sourcef,b.filename,b.lineno,b.entry from regold a right join regnew b on a.filename=b.filename and a.entry=b.entry where a.entry is null  
  order by filename,lineno,sourcef 
) TO '"+outdir+"/diffList.csv' delimiter ',' CSV HEADER;"
conn.exec(s)



