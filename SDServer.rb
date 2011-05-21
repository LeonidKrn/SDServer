require 'gserver'
require 'active_record'

ActiveRecord::Base.establish_connection(:adapter=>"sqlite3",:database=>"test.sqlite3",:host=>"localhost",:username=>"leonid")
=begin
ActiveRecord::Schema.define do
    #drop_table :fields
    #drop_table :plants
    #drop_table :users

    create_table :fields do |table|
        table.column :x, :integer
        table.column :y, :integer
        table.column :user_id, :integer
        table.column :plant_id, :integer     
    end

    create_table :plants do |table|
        table.column :plant_name, :string
    end

    create_table :users do |table|
        table.column :username, :string
    end
end
=end
class Field < ActiveRecord::Base
  belongs_to :user
  belongs_to :plant
end

class User < ActiveRecord::Base
    has_many :fields
end

class Plant < ActiveRecord::Base
    has_many :fields
end

def to_byte_array(num)
  result = []
  begin
    result << (num & 0xff)
    num >>= 8
  end until (num == 0 || num == -1) && (result.last[7] == num[7])
  result.reverse
end

class FarmServer < GServer
  
  def initialize(*args)
    super(*args)
    xmlfile = "crossdomain.xml"
    if File.exists?(xmlfile)
      @@xmldata=IO.read(xmlfile)
    else
      @@xmldata="<?xml version=\"1.0\"?>\n\<cross-domain-policy>\n\<allow-access-from domain=\"*\" to-ports=\"*\" />\n\</cross-domain-policy>"
    end
    #$/="\0"
    @messages=[]
    @clients=Hash::new
    @caller=Array::new
    @handlers={"connection"=>["connection_handler","user_alias"],"addvegy"=>["addvegy_handler","x","y","type"],"harvesting"=>["harvesting_handler","x","y"],"newday"=>["newday_handler"],"eop"=>["eop"]}
    
  end
  def serve(io)
    @clients[io]=Array::new
    count=0
    loop do
      if IO.select([io],nil,nil,2)   
          line=io.gets
          if line =~ /policy-file-request/
            @@xmldata+="\0"
            io.puts(@@xmldata)
            skip
          end      
          if !(line.nil?)
            #puts count
            @clients[io] << line.chomp
            #@messages << line#.chomp.lstrip
            count+=1
            #puts @clients[io].inspect
            puts @clients.inspect
            #puts("\0\nfield\0\ndata\0\x05<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<item type=\"0\" x=\"0\" y=\"0\" size=\"1\" />\0")
            #io.write(0x05)
            #"field\n".each_byte{|c| io.write(to_byte_array(c))}
            #io.puts("hello\0")
            #io.flush
            #"field\ndata\n<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<field><item type=\"0\" x=\"0\" y=\"0\" size=\"1\" />\n</field>\0".each_byte{|c| io.write('\\'+c.to_s)}
      
            # io.write("field")  
            # io.write("data")  
            # io.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<field><item type=\"0\" x=\"0\" y=\"0\" size=\"1\" />\n</field>\0")  
            # io.write("\n{EOP}\0")
            #io.puts("\0\nfield\0\ndata\0\x05<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<item type=\"0\" x=\"0\" y=\"0\" size=\"1\" />\0")
            #io.flush
            #io.puts("{EOP}")
            #io.write(fieldstring(io))  
            dispatchqueue(io)
          end

      end
    end
  end
  def eop(*args)
    #Dummy
  end
  def method_missing(method, arg)
    puts "Called: #{method}"
  end
  def newday_handler(io)
    puts "newday_handler"
    Field.find(:all).each do |rec|
      rec.stage+=1 if rec.stage<5
      rec.save
    end  
  end
  def dispatchqueue(io)
    puts "caller1="+@caller.inspect
    while @handlers[@clients[io][0]].nil? and @clients[io].length>0 and @caller.length==0 do
      puts "arp"
      @clients[io].shift   
    end
    while @caller.length>0 and @handlers[@caller[0]].nil? 
       @caller.shift
    end
    @clients[io].each do |mes|
      if @caller.length>0
        puts (@handlers[@caller[0]].length*2-1).to_s+" == "+@caller.length.to_s
      end
      
      if (@caller.length>0) and (!@handlers[mes].nil? or (@handlers[@caller[0]].length*2-1)==(@caller.length))
        puts "caller="+@caller.inspect
        puts "calling "+@caller[0].to_s
        send(@caller[0],io)
        @caller=[]
      else
        puts "caller="+@caller.inspect
      end
      if @clients[io].length>0
        @caller << @clients[io].shift
      end
    end        
  end
  def fieldstring(io)
    str=""
    str+="<country>\n<field zero_x=\"0\" zero_y=\"0\" size_x=\"70\" size_y=\"70\">\n"
    Field.find(:all).each do |rec|
      str+="<"
      str+=rec.plant.plant_name
      str+=" id=\""+rec.plant.id.to_s+"\" "
      str+="x=\"#{rec.x}\" y=\"#{rec.y}\" stage=\"#{rec.stage}\">\n"
    end
    str+="</field>\n</country>\0"
    return str.delete("<").delete(">")
  end
end

server=FarmServer.new(5566)
server.audit=true
#puts server.fieldstring nil
server.start

loop do 
  
  break if server.stopped?
end
