#!/opt/ruby/bin/ruby

require "rubygems"
require "awesome_print"
require "logger"
require "mysql"
require "trollop"


def pick_db(dbname)
  begin
    db = Mysql.new('localhost', 'zimbra', ENV['zimbra_mysql_password'], dbname, 7306, '/opt/zimbra/db/mysql.sock')
  rescue Mysql::Error => e
    ap e
    puts "Could not connect to Zimbra DB..."
    exit
  end
end

def get_msg_vol_id(db, mbox_id, msg_id, mod_content)
  begin
    res = db.query("SELECT volume_id FROM mail_item WHERE mailbox_id=#{mbox_id} AND id=#{msg_id} AND mod_content=#{mod_content}")
  rescue Mysql::Error => e
    ap e
	exit
  end
end

def get_msg_dumpster_vol_id(db, mbox_id, msg_id, mod_content)
  begin
    res = db.query("SELECT volume_id FROM mail_item_dumpster WHERE mailbox_id=#{mbox_id} AND id=#{msg_id} AND mod_content=#{mod_content}")
  rescue Mysql::Error => e
    ap e
	exit
  end
end

def update_entry(db, mbox_id, msg_id, mod_content, vol_id)
  begin
    $log.warn("UPDATE mail_item SET volume_id=#{vol_id} WHERE mailbox_id=#{mbox_id} AND id=#{msg_id} AND mod_content=#{mod_content}")
    res = db.query("UPDATE mail_item SET volume_id=#{vol_id} WHERE mailbox_id=#{mbox_id} AND id=#{msg_id} AND mod_content=#{mod_content}") if !opts[:test]
  rescue Mysql::Error => e
	$log.fatal("DATABASE ERROR!")
    puts e.errno
	$log.fatal(e.errno)
	puts e.error
	$log.fatal(e.error)
	exit
  end
end

def update_dumpster_entry(db, mbox_id, msg_id, mod_content, vol_id)
  begin
    $log.warn("UPDATE mail_item_dumpster SET volume_id=#{vol_id} WHERE mailbox_id=#{mbox_id} AND id=#{msg_id} AND mod_content=#{mod_content}")
    res = db.query("UPDATE mail_item_dumpster SET volume_id=#{vol_id} WHERE mailbox_id=#{mbox_id} AND id=#{msg_id} AND mod_content=#{mod_content}") if !opts[:test]
  rescue Mysql::Error => e
	$log.fatal("DATABASE ERROR!")
    puts e.errno
	$log.fatal(e.errno)
	puts e.error
	$log.fatal(e.error)
	exit
  end
end

# MAIN

# zmsetvars

if ENV['zimbra_mysql_password'].nil?
  puts "Must set Zimbra ENV first ($ source ~/bin/zmshutil; zmsetvars) ...exiting..."
  exit
end

opts = Trollop::options do
  opt :path, "Volume path", :type => :string
  opt :account, "Account", :type => :string
  opt :test, "Test Mode - DO NOT UPDATE DB"
end

Trollop::die :path, "must exist" if opts[:path] == nil
$log = Logger.new("/opt/zimbra/backup/repair_logs/repair_blobs-#{Time.now}.txt")
$log.level = Logger::INFO

zmvolume = `zmvolume -l`.split("compressed")
vol_hash = Hash.new
zmvolume.each do |entry|
  vol_hash[entry[/path: (.*)/, 1]] = entry[/Volume id: (.*)/, 1]
end

path = opts[:path]

if !vol_hash.include?(path)
  puts "INCORRECT VALUE SPECIFIED FOR --path" 
  exit
else
  vol_id = vol_hash[path]
end

if opts[:account] == nil
  account = nil
else
  if opts[:account].include?("@test.com")
    account = opts[:account]
  else
    account = opts[:account] + "@test.com"
  end
  db = pick_db("zimbra")
  res = db.query("SELECT id FROM mailbox WHERE comment='#{account}';")
  begin
    selected_id = res.fetch_row.join("\s")
  rescue Exception => e
    if e.to_s.include?('NilClass')
      selected_id = nil
	  puts "Invalid account name...#{account}"
	  exit
    end
  end
end

complete_file = "/opt/zimbra/backup/repair_logs/completed_ids_vol-#{vol_id}.txt"
if !File.exists?(complete_file)
  File.new(complete_file, "w")
end

root_paths = ['0','1','2']

mailbox_ids = Array.new

root_paths.each do |p|
  base_path = "#{path}/#{p}"
  #ap base_path
  mailbox_ids = Dir.entries(base_path)
  mailbox_ids.each do |id|
    # HAVE WE PROCESED THIS ID ALREADY?
	found = File.readlines(complete_file).select { |line| line[/^#{id}\n/] } 
	next if found.include?("#{id}\n")
    base_path = "#{path}/#{p}/#{id}/msg"
    next if id.include?(".")
    if selected_id != nil
	  next if id != selected_id
	end

    msg_paths = Dir.entries(base_path)
	mbox_id = id
	if mbox_id.size > 2
	  if mbox_id[-2,2] == '00'
	    mbox_group = '100'
	  else
	    mbox_group = mbox_id[-2,2].to_i.to_s
	  end
	else
	  mbox_group = mbox_id
    end
    db = pick_db("mboxgroup#{mbox_group}")

	begin
	  res = db.query("SELECT comment FROM zimbra.mailbox WHERE id=#{id};")
	  mail = res.fetch_row.join("\s")
	  $log.info("PROCESSING MAILBOX: === #{mail} ===")
	rescue Exception => e
	  $log.info("UNKNOWN MAILBOX:  === #{id} ===")
	end

    msg_paths.each do |mp|
	  base_path = "#{path}/#{p}/#{id}/msg/#{mp}"
	  #ap base_path
	  next if mp.include?(".")
	  msgs = Dir.entries(base_path)
	  msgs.each do |msg|
	    next if msg == "." || msg == ".." || msg == "msg"
	    msg_id = msg.split("-")[0]
		mod_content = msg.split("-")[1].split(".")[0]
		begin
          entry_vol_id = get_msg_vol_id(db, mbox_id, msg_id, mod_content).fetch_row.join("\s")
		rescue Exception => e
		  if e.to_s.include?('NilClass')
		    entry_vol_id = nil
		  else
		    ap e
		    exit
          end
		end
		full_msg_path = "#{base_path}/#{msg}"
        if entry_vol_id.nil?
		  $log.info("NO DB ENTRY FOR: Message from #{full_msg_path} id=#{msg_id} from mailbox_id=#{mbox_group}")
		  $log.info("CHECKING mail_item_dumpster")
		  # CHECK mail_item_dumpster NOW
		  begin
		    entry_vol_id = get_msg_dumpster_vol_id(db, mbox_id, msg_id, mod_content).fetch_row.join("\s")
		  rescue Exception => e
		    if e.to_s.include?('NilClass')
		      entry_vol_id = nil
		    else
		      ap e
		      exit
		    end
		  end
          if entry_vol_id.nil?
		    $log.info("NO DB ENTRY IN mail_item_dumpster FOR: Message from #{full_msg_path} id=#{msg_id} from mailbox_id=#{mbox_group}")
	      elsif entry_vol_id == vol_id 
		    $log.info("ENTRY OK: Message #{full_msg_path} id=#{msg_id} from mailbox_id=#{mbox_group}") 
	      else
		    $log.info("FIXING ENTRY IN mail_item_dumpster: Message #{full_msg_path} id=#{msg_id} from mailbox_id=#{mbox_group}")
			res = update_dumpster_entry(db, mbox_id, msg_id, mod_content, vol_id)
		  end
		elsif entry_vol_id == vol_id
		  $log.info("ENTRY OK: Message #{full_msg_path} id=#{msg_id} from mailbox_id=#{mbox_group}")
		else
		  $log.info("FIXING ENTRY: Message #{full_msg_path} id=#{msg_id} from mailbox_id=#{mbox_group}")
		  res = update_entry(db, mbox_id, msg_id, mod_content, vol_id)
		end
	  end

	end
    # KEEP TRACK OF FINISHED IDS
    File.open(complete_file, 'a+') {|f| f.write("#{id}\n")}
    # STOPFILE
    if File.exists?('/opt/zimbra/backup/repair_logs/.stop')
      puts "Found STOPFILE"
	  $log.info("FOUND STOPFILE - EXITING")
	  exit
    end
  end

end
