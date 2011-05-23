require 'gserver'
require 'active_record'
require 'rexml/document'

ActiveRecord::Base.establish_connection(:adapter=>"sqlite3",:database=>"test.sqlite3",:host=>"localhost",:username=>"leonid")

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

class String
  def push_string(a)
    if a.is_a?(String)
      lenchar=""
      lenchar=a.length>255?((a.length/256).chr+(a.length-256*(a.length/256)).chr) : (0.chr+a.length.chr)
      concat lenchar
      concat a  
    end
  end
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
     @@configdata="<?xml version=\"1.0\"?>\n\<config>\n</config>"
    $/="\0"
    @messages=[]
    @clients=Hash::new
    @caller=Array::new
    @users=Hash::new
    @buffer=Hash::new
    @tompo=[]
    #@handlers={"connection"=>["connection_handler","user_alias"],"addvegy"=>["addvegy_handler","x","y","type"],"harvesting"=>["harvesting_handler","x","y"],"newday"=>["newday_handler"],"eop"=>["eop"]}
    @handlers={"connection"=>["connection_handler","user_alias"],"field"=>["addvegy_handler","data"],"crop"=>["crop_handler","x","y","type"],"gather"=>["harvesting_handler","x","y"],"newday"=>["newday_handler"],"eop"=>["eop"]}
    
  end
  def serve(io)
    @clients[io]=Array::new
    count=0

    loop do
      if IO.select([io],nil,nil,0.1)   
          line=io.gets
          if line =~ /policy-file-request/
            @@xmldata+="\0"
            io.puts(@@xmldata)
            skip
          end   
          if line =~ /config-file-request/
            @@configdata+="\0"
            io.puts(@@configdata)
            skip
          end    
          if !(line.nil?)
            #puts line
            if line.length>255
              
            end
            #@tompo << line
            @clients[io].push(line.chomp[1..-1])
            #count+=1
            #puts @clients.inspect
            #puts @tompo.inspect
            dispatchqueue(io)
           end
      end
    end

  end
  def push_field(io)
    
    doc = REXML::Document.new("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
    doc.add_element("field")
    User.where(:username=>"guest").first.fields.each do |f|
      inhash={}
      inhash["x"]=f.x.to_s
      inhash["y"]=f.y.to_s
      inhash["type"]=(f.plant_id-1).to_s
      inhash["size"]=f.stage.to_s    
      doc.root.add_element("item", inhash)    
    end
    string=""
    string.push_string("field\0")
    string.push_string("data\0")
    quer=""

            quer=doc.to_s.gsub(">",">\n")+"\0"
            #quer="<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\n<field>\n<item type=\"1\" x=\"4\" y=\"1\" size=\"2\" /> \n<item type=\"1\" x=\"5\" y=\"1\" size=\"2\" /> \n<item type=\"1\" x=\"6\" y=\"1\" size=\"2\" /> \n</field>\n"
            string.push_string(quer)
            string.push_string("{EOP}\0")
            io.write(string)#io.write("\000\005{EOF}")
            io.flush()

=begin
            quer=quer+"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\n"
            quer=quer+"<field>\n"
            quer=quer+"<item x=\"5\" y=\"3\" type=\"2\" size=\"0\" />\n"
            quer=quer+"<item x=\"3\" y=\"1\" type=\"0\" size=\"2\" />\n"
            quer=quer+"<item x=\"3\" y=\"3\" type=\"0\" size=\"2\" />\n"
            quer=quer+"<item x=\"3\" y=\"4\" type=\"0\" size=\"2\" />\n"
            quer=quer+"<item x=\"5\" y=\"3\" type=\"2\" size=\"2\" />\n"
            quer=quer+"<item x=\"5\" y=\"4\" type=\"2\" size=\"2\" />\n"
            quer=quer+"<item x=\"6\" y=\"9\" type=\"2\" size=\"2\" />\n"
            quer=quer+("</field>\n")
=end

  end
  def eop(*args)
    #puts "ARGS: "+args.inspect
    str=fieldstring(args[0])
    #puts(str)
    args[0].puts(str)
    #Dummy
  end
  def method_missing(method, *args)
    #puts "Called: #{method}"
  end
  def crop_handler(*args)
    
    hash=args[1]
    puts args.inspect
    hash["x"]=hash["x"].to_i
    hash["y"]=hash["y"].to_i
    hash["type"]=hash["type"].to_i
    if @buffer[args[0]][{:x=>hash["x"], :y=>hash["y"]}].nil?
       @buffer[args[0]][{:x=>hash["x"], :y=>hash["y"]}]={:size=>0,:type=>hash["type"]}
    end
   puts "buffer, handling "+ @buffer[args[0]].inspect
  end
  def addvegy_handler(*args)

    hash=args[1]
    doc = REXML::Document.new(hash["data"])
    doc.elements.each('field/item') do |ele|
      inhash={}
      inhash[:x]=ele.attributes["x"].to_i
      inhash[:y]=ele.attributes["y"].to_i
      inhash[:stage]=ele.attributes["size"].to_i
      inhash[:plant_id]=(ele.attributes["type"].succ).to_i
      #puts inhash.inspect
      if User.where(:username=>@users[args[0]]).first.fields.where(:x=>inhash[:x],:y=> inhash[:y]).first.nil? 
        field=User.where(:username=>@users[args[0]]).first.fields.new
        field.x=inhash[:x]
        field.y=inhash[:y]
        field.stage=inhash[:stage]
        field.plant_id=inhash[:plant_id]
        field.save
        #User.where(:username=>@users[args[0]]).first.fields.create(inhash)
      end
     
    end
    send(@handlers["newday"][0],io)
    push_field(args[0]) 
  end
  def dbtobuffer(io)
    
    User.where(:username=>"guest").first.fields.each do |f|
      @buffer[io][{:x=>f.x,:y=>f.y}]={:stage=>f.stage,:type=>(f.plant_id-1)}
    end  
  end
  def connection_handler(*args)
    @users[args[0]]=args[1]["user_alias"]  
    @buffer[args[0]]=Hash::new
    dbtobuffer(args[0])
    push_field(args[0])       
  end
  def harvesting_handler(*args)
    hash=args[1]
    hash["x"]=hash["x"].to_i
    hash["y"]=hash["y"].to_i
    if !@buffer[args[0]][{:x=>hash["x"], :y=>hash["y"]}].nil?
      if @buffer[args[0]][{:x=>hash["x"], :y=>hash["y"]}][:size]>=4
        @buffer[args[0]].delete[{:x=>hash["x"], :y=>hash["y"]}]
      end
    end
    puts hash.inspect
     puts "buffer, handling "+ @buffer[args[0]].inspect
  end  
  def newday_handler(*args)
    #puts "newday_handler"
    User.where(:username=>"guest").first.fields.find(:all).each do |rec|
      if rec.stage.nil?
        rec.delete
      else      
        rec.stage+=1 if rec.stage<5
        rec.save
      end
    end  
  end
  def dispatchqueue(io)
    #puts "caller1="+@caller.inspect
    while @handlers[@clients[io][0]].nil? and @clients[io].length>0 and @caller.length==0 do
      puts "arp"
      @clients[io].shift   
    end
    while @caller.length>0 and @handlers[@caller[0]].nil? 
       @caller.shift
    end
    @clients[io].each do |mes|
      if @clients[io].length>0
        @caller << @clients[io].shift
      end
      if @caller.length>0
        #puts (@handlers[@caller[0]].length*2-1).to_s+" == "+@caller.length.to_s
      end
      if (@caller.length>0) and ((@handlers[@caller[0]].length*2-1)<=(@caller.length))# or !@handlers[mes].nil?)
        #puts "caller="+@caller.inspect
        #puts "calling "+@caller[0].to_s
        parametershash={}
        @handlers[@caller[0]].each do |h|
            ind=@caller[1..@caller.length-1].index(h)
            #puts h
            #puts ind
            if !ind.nil?
              parametershash[h]=@caller[1..@caller.length-1][ind+1]
            end
        end
        #puts parametershash.inspect
        send(@handlers[@caller[0]][0],io,parametershash)
        @caller=[]  
      else
        #puts "caller="+@caller.inspect
      end

    end  
    if @clients[io].length>0 and @caller.length>0
      dispatchqueue(io)      
    end      
  end
=begin
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
=end
end


server=FarmServer.new(5566)
server.audit=true
#puts server.fieldstring nil
server.start

loop do 
  
  break if server.stopped?
end
