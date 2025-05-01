require 'cbor'
data = {"id_item":2, "item1":101, "more": { "item2":12, "item3":3.14, "item4":"Example", "item5":[4, 3, 2, 1] } }
File.open("_cbor_template.bin", 'wb') do |file|
  file.write(data.to_cbor)
end
