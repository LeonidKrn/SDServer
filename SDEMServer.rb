require 'rubygems'
require 'eventmachine'
require 'active_record'
require 'rexml/document'

class String
  def push_string(a)
    if a.is_a?(String)
      lenchar=""
      lenchar=a.length>255?((a.length/256).chr+(a.length-256*(a.length/256)).chr) : (0.chr+a.length.chr)
      concat lenchar
      concat a  
    end
  end
  def byte_array_to_string_array
    return nil if length<2
    array=Array::new
    str=self.dup
    while str.length>1 do
      len=str.getbyte(0)*256+str.getbyte(1)
      str.slice!(0,2)      
      array.push str.slice!(0,len)
    end
    array
  end
end

ActiveRecord::Base.establish_connection(:adapter=>"sqlite3",:database=>"farm.sqlite3",:host=>"localhost")

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
module FarmServerModule
  

  def connection_handler(*args) #Обработчик команды соединения с сервером
    @users=args[0]["user_alias"]  
    if User.where(:username=>@users).nil?
      User.create(:username=>@users)
    end
    @buffer=Hash::new
    dbtobuffer() if @buffered 
    push_field()  
    @timer = EventMachine::PeriodicTimer.new(@period) do
      periodic_handler()
    end
    @timer1 = EventMachine::PeriodicTimer.new(@period*5) do
      buffertodb()
    end
  end
  def periodic_handler() #Периодический прирост растений
    newday_handler()
    push_field()   
  end
  def crop_handler(*args) #Обработка команды посадки растения
    hash=args[0]
    hash["x"]=hash["x"].to_i
    hash["y"]=hash["y"].to_i
    hash["type"]=hash["type"].to_i
    if @buffer[{:x=>hash["x"], :y=>hash["y"]}].nil?
       @buffer[{:x=>hash["x"], :y=>hash["y"]}]={:size=>0,:type=>hash["type"]}
    end
  end

  def push_field() #Функция пересылки данных о поле клиенту 
    doc = REXML::Document.new("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
    doc.add_element("field")
    if @buffered
      @buffer.each_pair do |xy,sizetype| 
        inhash={}
        inhash["x"]=xy[:x].to_s
        inhash["y"]=xy[:y].to_s
        inhash["type"]=sizetype[:type].to_s
        inhash["size"]=sizetype[:size].to_s    
        doc.root.add_element("item", inhash)     
      end
    else
      User.where(:username=>@users).first.fields.each do |f|
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
    send_data string
  end

  

  def dbtobuffer() #Выгрузка базы данных в буферный хэш
    @buffer=Hash::new
    User.where(:username=>@users).first.fields.each do |f|
      @buffer[{:x=>f.x,:y=>f.y}]={:size=>f.stage,:type=>(f.plant_id-1)}
    end  
  end

  def buffertodb() #Выгрузка буфера в БД
    @buffer.each_pair do |xy,stagetype|
      field=User.where(:username=>@users).first.fields
      if field.where(xy).first.nil?
        field.create(xy.merge({:stage=>stagetype[:size],:plant_id=>(stagetype[:type]+1)}))    
      else
        field.where(xy).first.update_attributes(:stage=>stagetype[:size],:plant_id=>(stagetype[:type]+1))
      end
    end
    User.where(:username=>@users).first.fields.each do |f|
      if @buffer[{:x=>f.x,:y=>f.y}].nil?
        f.delete
      end
    end
  end

  def harvesting_handler(*args) #Обработчик команды сбора урожая 
    hash=args[0]
    hash["x"]=hash["x"].to_i
    hash["y"]=hash["y"].to_i
    if !@buffer[{:x=>hash["x"], :y=>hash["y"]}].nil?
      if @buffer[{:x=>hash["x"], :y=>hash["y"]}][:size]>=4
        @buffer.delete({:x=>hash["x"], :y=>hash["y"]})
      end
    end
  end  


  def newday_handler(*args) #Обработчик команды следующего хода
    if @buffered
      @buffer.each_value do |v|
        if v[:size]<4
          v[:size]+=1
        end
      end
    else    
      User.where(:username=>@users).first.fields.find(:all).each do |rec|
        if rec.stage.nil?
          rec.delete
        else      
          rec.stage+=1 if rec.stage<5
          rec.save
        end
      end  
    end
  end

  def data_dispatcher(data)
    array=data.byte_array_to_string_array
    array.delete("{EOP}") 
    parametershash={}
    @handlers[array[0]].each do |h|
      ind=array[1..array.length-1].index(h)
      if !ind.nil?
        parametershash[h]=array[1..array.length-1][ind+1]
      end
    end
    array=[@handlers[array[0]][0],parametershash]
    send(array[0],array[1])
  end
end
class FarmServer < EventMachine::Connection
  include FarmServerModule
  @@xmldata="<?xml version=\"1.0\"?>\n\<cross-domain-policy>\n\<allow-access-from domain=\"*\" to-ports=\"*\" />\n\</cross-domain-policy>"
	def post_init
    $/="\0"
    @buffer=nil
    @buffered=true
    @handlers={"connection"=>["connection_handler","user_alias"],"field"=>["addvegy_handler","data"],"crop"=>["crop_handler","x","y","type"],"gather"=>["harvesting_handler","x","y"],"newday"=>["newday_handler"],"eop"=>["eop"]}
    @users=""
    @policy_checker=false
    @timer=nil
    @timer1=nil
    @period=10
	end

	def receive_data data  
    if data =~ /policy-file-request/
      @policy_checker=true
      send_data @@xmldata+"\0"
      return
    end 
		close_connection if data =~ /quit/i
    data_dispatcher(data)
	end

	def unbind
    buffertodb() if !@policy_checker
	end
end

EventMachine::run {
	EventMachine::start_server '', 5566, FarmServer
}
