require_relative '../app/api'

ShipReqs = Norairrecord.table(ENV['AIRTABLE_PAT'], 'appK53aN0fz3sgJ4w', 'tbltnDSvmiUH0grQo')


puts "fetching orders that need costed..."
orders = Quartermaster::ShopOrder.records filter: "AND({shop_item:fulfillment_type}='agh', status='fulfilled', warehouse_cost=BLANK())"
puts "got #{orders.length} of them!"
orders.each do |order|
  puts "processing order #{order.id}"
  /<MarketingShipmentRequest id='(?<shipreq_id>.*)'>/i =~ order['external_ref']
  unless shipreq_id
    puts "\tHEY! order #{order.id} doesn't actually have a shipreq in ref!!"
    next
  end
  puts "\tfetching shipment request #{shipreq_id}"
  begin
    shipreq = ShipReqs.find shipreq_id
  rescue Norairrecord::Error
    puts "\tHEY!! #{shipreq_id} isn't valid!"
    next
  end
  unless shipreq["Warehouse–Postage Cost"]
    puts "\thasn't been mailed yet..."
    next
  end

  order.patch("warehouse_cost"=>shipreq["Warehouse–Total Cost"])
  puts "\tupdated!"
end