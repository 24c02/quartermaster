require_relative './hcb_api'
module Quartermaster
  def self.fulfill_hcb_grant(o)
    amount_cents = o.item['hcb_grant_amount_cents'] * o.order['quantity']
    email = o.order['hcb_email']
    allowed_merchants = o.item['hcb_grant_merchants']

    latest_disbursement = memo = nil

    grant_rec = ShopCardGrant.lookup_or_create(o.recipient, o.item)

    grant_rec.transaction do
      if grant_rec.new_record?
        puts "creating grant for #{email} of #{amount_cents} cents with merchant lock #{allowed_merchants}..."
        grant = HCBAPI.create_card_grant(
          email:,
          allowed_merchants:,
          amount_cents:
        )

        grant_rec['disbursement_log'] = ""
        grant_rec['hcb_grant_hashid'] = grant.id
        grant_rec['expected_amount_cents'] = amount_cents
        latest_disbursement = grant.disbursements[0].transaction_id
        memo = "[grant] #{o.item['name']} for #{grant.user&.name || o.person.nice_full_name}"
      else
        hashid = grant_rec['hcb_grant_hashid']
        puts "topping up #{hashid} by #{amount_cents} cents..."

        topup = HCBAPI.topup_card_grant(hashid:, amount_cents:)

        latest_disbursement = topup.disbursements[0].transaction_id
        grant_rec['expected_amount_cents'] = (grant_rec['expected_amount_cents'] || 0) + amount_cents
        memo = "[grant] topping up  #{topup.user&.name || o.person.nice_full_name}'s #{o.item['name']}"
      end
      puts "got #{latest_disbursement}!"

      grant_rec['disbursement_log'] = "#{grant_rec['disbursement_log']}#{Time.now.utc.iso8601}: #{latest_disbursement} of #{amount_cents} cents\n"
    end
    begin
      HCBAPI.rename_transaction(hashid: latest_disbursement, new_memo: memo)
    rescue StandardError => e
      pp e
      Yap.post_to_ops("<@U06QK6AG3RD>: couldn't rename #{latest_disbursement} while fulfilling #{o.order.slack_url} (#{grant_rec.slack_url})")
    end
    o.order.mark_fulfilled(ref: grant_rec, slack_ref: grant_rec.slack_url)
  end
end