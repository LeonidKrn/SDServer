require 'gserver'
require 'active_record'
require 'rexml/document'

ActiveRecord::Base.establish_connection(:adapter=>"sqlite3",:database=>"farm.sqlite3",:host=>"localhost",:username=>"leonid")

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
    $/="\0"
    @messages=[]
    @clients=Hash::new
    @caller=Hash::new
    @users=Hash::new
    @buffer=Hash::new
    @tompo=[]
    @buffered=true
    @ready_to_grow=Hash::new
    @threads=Hash::new
    @handlers={"connection"=>["connection_handler","user_alias"],"field"=>["addvegy_handler","data"],"crop"=>["crop_handler","x","y","type"],"gather"=>["harvesting_handler","x","y"],"newday"=>["newday_handler"],"eop"=>["eop"]}
    
  end
  
  def serve(io) #Основной цикл для приёма сообщений от клиентов
    @ready_to_grow[io]=false
    @threads[io]=Thread.new { loop { periodic_handler(io) if @ready_to_grow[io]; sleep 30 } }
    @clients[io]=Array::new
    @caller[io]=Array::new
    count=0

    loop do
      if IO.select([io],nil,nil,nil)   
          line=io.gets
          if line =~ /policy-file-request/
            @@xmldata+="\0"
            io.puts(@@xmldata)
            io.close
            next
          end   
          if !(line.nil?)
            count+=1
            if line.length>255
              
            end
            @clients[io].push(line.chomp[1..-1])

            dispatchqueue(io)

            
           end
      end
    end
 

  end
  def periodic_handler(io) #Периодический прирост растений
    newday_handler(io)
    push_field(io)   
    buffertodb(io) 
  end
 
  def push_field(io) #Функция пересылки данных о поле клиенту
    
    doc = REXML::Document.new("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
    doc.add_element("field")
    if @buffered
      @buffer[io].each_pair do |xy,sizetype| 
        inhash={}
        inhash["x"]=xy[:x].to_s
        inhash["y"]=xy[:y].to_s
        inhash["type"]=sizetype[:type].to_s
        inhash["size"]=sizetype[:size].to_s    
        doc.root.add_element("item", inhash)     
      end
    else
      User.where(:username=>@users[io]).first.fields.each do |f|
        inhash={}
        inhash["x"]=f.x.to_s
        inhash["y"]=f.y.to_s
        inhash["type"]=(f.plant_id-1).to_s
        inhash["size"]=f.stage.to_s    
        doc.root.add_element("item", inhash)    
      end
    end
    string=""
    string.push_string("field\0")
    string.push_string("data\0")
    quer=""
    quer=doc.to_s.gsub(">",">\n")+"\0"
    string.push_string(quer)
    string.push_string("{EOP}\0")
    io.write(string)
    io.flush()
  end

  def eop(*args) #Заглушка
    str=fieldstring(args[0])
    args[0].puts(str)
    #Dummy
  end

  def method_missing(method, *args)
    #puts "Called: #{method}"
  end

  def crop_handler(*args) #Обработка команды посадки растения
    
    hash=args[1]
    #puts args.inspect
    hash["x"]=hash["x"].to_i
    hash["y"]=hash["y"].to_i
    hash["type"]=hash["type"].to_i
    if @buffer[args[0]][{:x=>hash["x"], :y=>hash["y"]}].nil?
       @buffer[args[0]][{:x=>hash["x"], :y=>hash["y"]}]={:size=>0,:type=>hash["type"]}
    end
    buffertodb(args[0])
  end

  def addvegy_handler(*args) #Обработка команды посадки растения в xml формате, пока не используется
    hash=args[1]
    doc = REXML::Document.new(hash["data"])
    doc.elements.each('field/item') do |ele|
      inhash={}
      inhash[:x]=ele.attributes["x"].to_i
      inhash[:y]=ele.attributes["y"].to_i
      inhash[:stage]=ele.attributes["size"].to_i
      inhash[:plant_id]=(ele.attributes["type"].succ).to_i
      if User.where(:username=>@users[args[0]]).first.fields.where(:x=>inhash[:x],:y=> inhash[:y]).first.nil? 
        field=User.where(:username=>@users[args[0]]).first.fields.new
        field.x=inhash[:x]
        field.y=inhash[:y]
        field.stage=inhash[:stage]
        field.plant_id=inhash[:plant_id]
        field.save
      end
    end
    send(@handlers["newday"][0],io)
    push_field(args[0]) 
  end

  def dbtobuffer(io) #Выгрузка базы данных в буферный хэш
    @buffer[io]=Hash::new
    User.where(:username=>@users[io]).first.fields.each do |f|
      @buffer[io][{:x=>f.x,:y=>f.y}]={:size=>f.stage,:type=>(f.plant_id-1)}
    end  
  end

  def buffertodb(io) #Выгрузка буфера в БД
    @buffer[io].each_pair do |xy,stagetype|
      field=User.where(:username=>@users[io]).first.fields
      if field.where(xy).first.nil?
        field.create(xy.merge({:stage=>stagetype[:size],:plant_id=>(stagetype[:type]+1)}))    
      else
        field.where(xy).first.update_attributes(:stage=>stagetype[:size],:plant_id=>(stagetype[:type]+1))
      end
    end
    User.where(:username=>@users[io]).first.fields.each do |f|
      if @buffer[io][{:x=>f.x,:y=>f.y}].nil?
        f.delete
      end
    end
  end

  def connection_handler(*args) #Обработчик команды соединения с сервером
    @users.each_pair do |io,user|
      if user==args[1]["user_alias"] and !io.closed?
        io.close
      end
      
    end
     
    @users[args[0]]=args[1]["user_alias"]  
    if User.where(:username=>@users[args[0]]).nil?
      User.create(:username=>@users[args[0]])
    end
    @buffer[args[0]]=Hash::new
    dbtobuffer(args[0]) if @buffered 
    push_field(args[0])    
    @ready_to_grow[args[0]]=true  

  end

  def harvesting_handler(*args) #Обработчик команды сбора урожая 
    hash=args[1]
    hash["x"]=hash["x"].to_i
    hash["y"]=hash["y"].to_i
    if !@buffer[args[0]][{:x=>hash["x"], :y=>hash["y"]}].nil?
      if @buffer[args[0]][{:x=>hash["x"], :y=>hash["y"]}][:size]>=4
        @buffer[args[0]].delete({:x=>hash["x"], :y=>hash["y"]})
      end
    end
    buffertodb(args[0])
  end  


  def newday_handler(*args) #Обработчик команды следующего хода
    if @buffered
      @buffer[args[0]].each_value do |v|
        if v[:size]<4
          v[:size]+=1
        end
      end
    else    
      User.where(:username=>@users[args[0]]).first.fields.find(:all).each do |rec|
        if rec.stage.nil?
          rec.delete
        else      
          rec.stage+=1 if rec.stage<5
          rec.save
        end
      end  
    end
  end

  def dispatchqueue(io) #Разборщик очереди команд от клиента

    #Вырезка мусора из очереди команд клиента
    while @handlers[@clients[io][0]].nil? and @clients[io].length>0 and @caller[io].length==0 do
      @clients[io].shift  
    end
    
    #Вырезка мусора из последовательности вызова функций
    while @caller[io].length>0 and @handlers[@caller[io][0]].nil? 
       @caller[io].shift
    end
    
    @clients[io].each do |mes|
      if @clients[io].length>0
        @caller[io] << @clients[io].shift
      end
      if @caller[io].length>0
      end
      #Поиск в хэше обработчиков команды с полученным названием и сверка с набором параметров
      if (@caller[io].length>0) and ((@handlers[@caller[io][0]].length*2-1)<=(@caller[io].length))# or !@handlers[mes].nil?)
        parametershash={}
        @handlers[@caller[io][0]].each do |h|
            ind=@caller[io][1..@caller[io].length-1].index(h)
            if !ind.nil?
              #Создание хэша параметров для вызываемой функции
              parametershash[h]=@caller[io][1..@caller[io].length-1][ind+1]
            end
        end
        #Вызов обработчика
        send(@handlers[@caller[io][0]][0],io,parametershash)
        @caller[io]=[]  
      end
    end  
    if @clients[io].length>0 and @caller[io].length>0
      dispatchqueue(io)      
    end      
  end

end


server=FarmServer.new(5566)
server.start
server.audit=true
server.join

#loop do 
#  break if server.stopped?
#end

