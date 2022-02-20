module Receipts
    class Payslip < Base
      @title = "Payslip"
      
      def default_message(company:)
        "For questions, contact us anytime at <color rgb='326d92'><link href='mailto:#{company.fetch(:email)}?subject=Question about my receipt'><b>#{company.fetch(:email)}</b></link></color>."
      end
    end
  end
  