require 'active_record'


ActiveRecord::Base.establish_connection(:adapter=>"sqlite3",:database=>"farm.sqlite3",:host=>"localhost")
begin
  ActiveRecord::Schema.drop_table(:fields)
  ActiveRecord::Schema.drop_table(:plants)
  ActiveRecord::Schema.drop_table(:users)
rescue
  nil
end
ActiveRecord::Schema.define do


    create_table :fields do |table|
        table.column :x, :integer
        table.column :y, :integer
        table.column :stage, :integer
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
plnts=[]
user=User.create(:username=>"guest")
plnts << (plant1=Plant.create(:plant_name=>"plant1"))
plnts << (plant2=Plant.create(:plant_name=>"plant2"))
plnts << (plant3=Plant.create(:plant_name=>"plant3"))

for x in 0..12 do
  for y in 0..12 do
    if rand(13*13/5)==1
      user.fields.create(:x=>x,:y=>y,:plant_id=>plnts[rand(plnts.length)].id, :stage=>(rand(5)))
    end
  end 
end
puts Field.all.inspect
