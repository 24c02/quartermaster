require_relative './hcb_api'
module Quartermaster
  class GrantCanceledError < StandardError; end

  def self.fulfill_hcb_grant(o)
    amount_cents = o.item['hcb_grant_amount_cents'] * o.order['quantity']
    email = o.order['hcb_email']
    merchant_lock = o.item['hcb_grant_merchants']
    keyword_lock= o.item['hcb_grant_keyword_regex']

    if o.order["dont_merge_hcb"]
      grant = HCBAPI.create_card_grant(
        email:,
        merchant_lock:,
        amount_cents:,
        keyword_lock:
      )

      latest_disbursement = grant.disbursements[0].transaction_id
      memo = "[grant] #{o.item['name']} for #{grant.user&.name || o.person.nice_full_name}"
      HCBAPI.rename_transaction(hashid: latest_disbursement, new_memo: memo)
      o.order.mark_fulfilled(ref: "https://hcb.hackclub.com/grants/#{grant.id[-6..]}")
      return
    end

    latest_disbursement = memo = nil

    grant_rec = ShopCardGrant.lookup_or_create(o.recipient, o.item)
    user_canceled = false

    grant_rec.transaction do
      begin
        if grant_rec.new_record? || user_canceled
          puts "creating grant for #{email} of #{amount_cents} cents with merchant lock #{merchant_lock}..."
          grant = HCBAPI.create_card_grant(
            email:,
            merchant_lock:,
            amount_cents:
          )

          grant_rec['disbursement_log'] = "" unless grant_rec['disbursement_log']
          if user_canceled
            grant_rec['disbursement_log'] << "user canceled previous grant #{grant_rec['hcb_grant_hashid']}, starting over >:-/\n\n"
          end
          grant_rec['hcb_grant_hashid'] = grant.id
          grant_rec['expected_amount_cents'] = amount_cents
          latest_disbursement = grant.disbursements[0].transaction_id
          memo = "[grant] #{o.item['name']} for #{grant.user&.name || o.person.nice_full_name}"
        else

          hashid = grant_rec['hcb_grant_hashid']

          puts "getting grant"
          hcb_grant = HCBAPI.show_card_grant(hashid:)
          # we shouldn't have to touch the stripe card here, waiting on gary to merge #8894 to fix that
          puts "getting card"
          begin
            if hcb_grant.card_id
              hcb_stripe_card = HCBAPI.show_stripe_card(hashid: hcb_grant.card_id)
              raise GrantCanceledError if hcb_stripe_card.status != 'active'
            end
          rescue HCBError => e
            puts e.message, e.backtrace[..2]
          end

          puts "topping up #{hashid} by #{amount_cents} cents..."

          topup = HCBAPI.topup_card_grant(hashid:, amount_cents:)

          latest_disbursement = topup.disbursements[0].transaction_id
          grant_rec['expected_amount_cents'] = (grant_rec['expected_amount_cents'] || 0) + amount_cents
          memo = "[grant] topping up  #{topup.user&.name || o.person.nice_full_name}'s #{o.item['name']}"
        end
      puts "got #{latest_disbursement}!"

      grant_rec['disbursement_log'] = "#{grant_rec['disbursement_log']}#{Time.now.utc.iso8601}: #{latest_disbursement} of #{amount_cents} cents\n"
      rescue GrantCanceledError => e
        user_canceled = true
        puts "canceled 🤯🤯"
        retry
      end
    end
    begin
      HCBAPI.rename_transaction(hashid: latest_disbursement, new_memo: memo)
    rescue StandardError => e
      pp e
      Yap.post_to_ops("<@U06QK6AG3RD>: couldn't rename #{latest_disbursement} while fulfilling #{o.order.slack_url} (#{grant_rec.slack_url})")
    end
    o.order["card_grant_rec"] = [grant_rec.id]
    o.order.mark_fulfilled(ref: grant_rec, slack_ref: grant_rec.slack_url)
  end
end
