require 'gserver'
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
    @handlers=[:connection,:addvegy,:harvesting,:newday,:somethingelse]
    
  end
  def serve(io)
    @clients[io]=Array::new
    count=0
    loop do
      if IO.select([io],nil,nil,nil)   
          line=io.gets
          if line =~ /policy-file-request/
            @@xmldata+="\0"
            io.puts(@@xmldata)
            skip
          end      
          if !(line.nil?)
            #puts count
            @clients[io] << line
            #@messages << line#.chomp.lstrip
            count+=1
            #puts @clients[io].inspect
            puts @clients.inspect
            #puts("\0\nfield\0\ndata\0\x05<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<item type=\"0\" x=\"0\" y=\"0\" size=\"1\" />\0")
            #io.write(0x05)
            #"field\n".each_byte{|c| io.write(to_byte_array(c))}
            #io.puts("hello\0")
            #io.flush
            "field\ndata\n<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<field><item type=\"0\" x=\"0\" y=\"0\" size=\"1\" />\n</field>\0".each_byte{|c| io.write('\\'+c.to_s)}
            io.write("fieldsd\0")        
            # io.write("field")  
            # io.write("data")  
            # io.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<field><item type=\"0\" x=\"0\" y=\"0\" size=\"1\" />\n</field>\0")  
            # io.write("\n{EOP}\0")
            #io.puts("\0\nfield\0\ndata\0\x05<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<item type=\"0\" x=\"0\" y=\"0\" size=\"1\" />\0")
            #io.flush
            #io.puts("{EOP}")
          end

      end
    end
  end
  def dispatchqueue(io)
          
  end
end

server=FarmServer.new(5566)
server.audit=true
server.start

loop do 
  
  break if server.stopped?
end
