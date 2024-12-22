module Quartermaster
  EU_COUNTRIES = [
    "Austria",
    "Belgium",
    "Bulgaria",
    "Croatia",
    "Cyprus",
    "Czech Republic",
    "Denmark",
    "Estonia",
    "Finland",
    "France",
    "Germany",
    "Greece",
    "Hungary",
    "Italy",
    "Latvia",
    "Lithuania",
    "Luxembourg",
    "Malta",
    "Netherlands",
    "Poland",
    "Portugal",
    "Romania",
    "Slovakia",
    "Spain",
    "Sweden"
  ]

  class Reject < StandardError; end

  class << self
    def reject(msg)
      raise Reject, msg
    end

    def validate!(order)
      begin
        reject "what do you even want?" unless order.item
        item = order.item
        reject "who are you?!?!" unless order.recipient
        person = order.recipient

        reject "how??" if person['freeze_activity']

        freeze_address(order, person)
        person.invalidate_otp!

        if person['shop_hold_all_orders']
          order['status'] = 'on_hold'
          order.save
          return 'eyyyyy'
        end

        item_is_free_stickers = item.id == "recHByvKaaeXaGsPq"

        reject "you've already ordered some!" if item_is_free_stickers && person['free_stickers_dupe_check']

        order['quantity'] ||= 1 # for old time's sake

        reject "ya gotta order at least one :-P" if order['quantity'] < 0

        reject "hey, this is awkward...you don't have a verification record? weird, please ask in <#C07PZNMBPBN>!" unless !person['YSWS Verification User']&.empty?
        reject "you've ascended past eligibility for this program..." if person['verification_alum'][0]
        reject "you're marked as ineligible for this program :-(" if person['verification_status'] == 'Ineligible'

        unless ['Eligible L1', 'Eligible L2'].include? person['verification_status'][0]
          reject "you need to <https://forms.hackclub.com/eligibility?program=High+Seas&slack_id=#{person['slack_id']}|verify your identity> first." unless item_is_free_stickers
          return order.pend_verification!
        end

        unless item['identifier'].end_with? 'wahoo'
          reject 'what are you trying to pull?' unless item['enabled'] || person['shop_dev']

          expected_price = item['tickets_us']
          if item['needs_addy']
            order_country = order['addr_country']

            if order['customs_acked']
              person['shop_customs_acked'] = true
              person.save
            end
            regional_enable =
              case order_country
              when "United States"
                item['enabled_us']
              when "India"
                item['enabled_in']
              when "Canada"
                item['enabled_ca']
              when *EU_COUNTRIES
                item['enabled_eu']
              when "United Kingdom", "Ireland", "England"
                item['enabled_uk']
              else
                item['enabled_xx']
              end
            reject "this item isn't available in your region." unless regional_enable

            if item['no_no_countries']
              reject "we can't ship that to #{order_country}" if item['no_no_countries'].split('|').include?(order_country)
            end

            expected_price = order_country == "United States" ? item['tickets_us'] : item['tickets_global']
          end

          reject "there was a pricing error? this shouldn't ever happen, please DM <@U06QK6AG3RD>." unless order['unit_price_paid'] == expected_price
        end

        reject "you can't afford it... come back when you're a little... mmmmm.... richer." if order['tickets_paid'] > person['settled_tickets']

        if item['skip_manual_validation'] || ENV['FOR_REALZ'] == 'yeah!'
          order.mark_in_flight
        else
          order.send_for_review
        end
        order.save
        "in_flight"
      rescue Reject => e
        order.reject e.message
        order.save
        return "rejected"
      end
    end

    def freeze_address(order, person)
      address = person.address # otherwise we hit airtable every iter -_-
      { 'addr_first_name' => 'first_name',
        'addr_last_name' => 'last_name',
        'addr_line1' => 'line_1',
        'addr_line2' => 'line_2',
        'addr_line3' => 'line_3',
        'addr_city' => 'city',
        'addr_state_province' => 'state_province',
        'addr_postal_code' => 'postal_code',
        'addr_country' => 'country',
        'addr_phone' => 'phone',
        'addr_seq' => 'sequence_number'
      }.each { |k, v| order[k] = address[v] }
    end
  end
end
