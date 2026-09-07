module Api
  module V1
    # The controlled vocabulary behind +assets.usage_terms+.
    #
    # The rights editor needs the list of valid terms, and hard-coding it in the
    # frontend would create a second copy of a vocabulary whose whole purpose is
    # to be authoritative. A term added or relabelled in {Rights::UsageTerms}
    # would then silently fail to appear in the only UI that can set it.
    class RightsController < ApplicationController
      before_action :authenticate_hybrid!
      # GET /api/v1/rights/usage_terms
      #
      # @return [void] renders +200 OK+ with the term codes, labels and whether
      #   each permits distribution outside the organisation
      def usage_terms
        render json: {
          usage_terms: Rights::UsageTerms::TERMS.map do |code, attrs|
            {
              code:     code,
              label:    attrs[:label],
              external: attrs[:external],
            }
          end,
          default: Rights::UsageTerms::DEFAULT,
        }
      end
    end
  end
end
