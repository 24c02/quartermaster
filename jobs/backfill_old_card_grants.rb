require_relative '../app/api'

include Quartermaster

old_cdg_orders = ShopOrder.records filter: 'AND({shop_item:fulfillment_type}="hcb_grant", {status}="fulfilled", {created_at}<"2024-11-10", NOT({temp_cdg_backfilled}))'

old_cdg_orders.each do |order|
  o = EnrichedOrder.new(order)
  grant_rec = ShopCardGrant.lookup_or_create(o.recipient, o.item)
  grant_rec.transaction do |grant|
    hashid = "cdg_" + o.order["external_ref"][-6..]
    hcbs_thoughts_on_the_matter = HCBAPI.show_card_grant(hashid:)

    grant_rec["hcb_grant_hashid"] = hashid
    grant_rec["expected_amount_cents"] = hcbs_thoughts_on_the_matter.amount_cents
    dl = "-- backfilled old disbursements: --\n"
    hcbs_thoughts_on_the_matter.disbursements.each do |disbursement|
      dl << "#{disbursement.transaction_id} of #{disbursement.amount_cents} cents\n"
    end
    dl << "-- end backfilled old disbursements --\n\n"
    grant_rec["disbursement_log"] = dl
    order["temp_cdg_backfilled"] = true
  end
end