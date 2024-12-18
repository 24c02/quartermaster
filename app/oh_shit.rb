module Quartermaster
  class << self
    def get_card_grants_for_user(person)
      hcb_emails = person.orders.map { |order| order['hcb_email'] }.compact
      HCBAPI.index_card_grants.select { |grant| hcb_emails.include? grant.user.email }
    end
    def fuck_em_up_card_wise!(person)
      grants = get_card_grants_for_user(person)
      grants.select! { |grant| grant.status == 'active' }
      grants.each do |grant|
        HCBAPI.cancel_card_grant! hashid: grant.id
      end
    end
    def fuck_em_up_order_wise!(person)
      person.orders.reject { |order| %i(fulfilled REJECTED error_fulfilling refunded).include? order.aasm.current_state }.each do |order|
        order.patch({"status"=>"REJECTED"})
      end
    end
  end
end