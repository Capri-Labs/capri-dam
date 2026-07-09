require "net/http"
require "uri"
require "jwt"

module Ims
  # Exchanges an Adobe IMS "Service Account (JWT)" technical account for a
  # short-lived access token.
  #
  # Flow (see Adobe docs — "Generating access tokens for server-side apps"):
  #   1. Build a JWT signed with the technical account's RSA private key
  #      (RS256), asserting the requested metascope(s).
  #   2. POST that JWT + client_id/client_secret to
  #      `https://<imsEndpoint>/ims/exchange/jwt`.
  #   3. Adobe returns a Bearer `access_token` (expires_in seconds).
  #
  # Security notes:
  #   - The private key / client secret never leave this process except as an
  #     already-signed JWT (the raw key is not transmitted).
  #   - Nothing here logs the private key, client secret, or resulting token.
  #   - Callers are expected to persist the result via
  #     SystemConnector#refresh_access_token!, which stores it through
  #     ActiveRecord Encryption (see SystemConnector `encrypts`).
  class JwtTokenExchangeService
    Error = Class.new(StandardError)

    JWT_TTL = 5.minutes

    def initialize(connector)
      @connector = connector
      @payload   = connector.credentials_payload || {}
    end

    # @return [Hash] { access_token:, expires_at: }
    def call
      validate_payload!

      signed_jwt = build_jwt
      response   = exchange(signed_jwt)

      {
        access_token: response.fetch("access_token"),
        expires_at:   Time.current + response.fetch("expires_in", 86_400).to_i.seconds,
      }
    end

    private

    attr_reader :connector, :payload

    def validate_payload!
      required = %w[client_id client_secret private_key technical_account_id org_id ims_endpoint metascopes]
      missing  = required.select { |k| payload[k].blank? }
      raise Error, "Missing IMS credential fields: #{missing.join(", ")}" if missing.any?
    end

    def build_jwt
      now = Time.current.to_i
      claims = {
        "iss" => payload["org_id"],
        "sub" => payload["technical_account_id"],
        "exp" => now + JWT_TTL.to_i,
        "aud" => "https://#{ims_endpoint}/c/#{payload["client_id"]}",
      }

      Array(payload["metascopes"].to_s.split(",")).each do |scope|
        claims["https://#{ims_endpoint}/s/#{scope.strip}"] = true
      end

      private_key = OpenSSL::PKey::RSA.new(payload["private_key"])
      JWT.encode(claims, private_key, "RS256")
    rescue OpenSSL::PKey::RSAError => e
      raise Error, "Invalid private key: #{e.message}"
    end

    def exchange(signed_jwt)
      uri = URI.parse("https://#{ims_endpoint}/ims/exchange/jwt")
      form = {
        "client_id"     => payload["client_id"],
        "client_secret" => payload["client_secret"],
        "jwt_token"     => signed_jwt,
      }

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
        req = Net::HTTP::Post.new(uri)
        req.set_form_data(form)
        http.request(req)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "IMS token exchange failed (HTTP #{response.code}): #{sanitized_body(response.body)}"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError
      raise Error, "IMS token exchange returned an unparsable response"
    end

    def ims_endpoint
      payload["ims_endpoint"].to_s.sub(%r{\Ahttps?://}, "").chomp("/")
    end

    # Adobe error responses don't echo secrets back, but strip defensively in
    # case of a proxy/error-page body reflecting request data.
    def sanitized_body(body)
      body.to_s.gsub(payload["client_secret"].to_s, "[REDACTED]")
    end
  end
end
