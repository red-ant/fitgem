require 'fitgem/version'
require 'fitgem/helpers'
require 'fitgem/errors'
require 'fitgem/users'
require 'fitgem/activities'
require 'fitgem/sleep'
require 'fitgem/water'
require 'fitgem/blood_pressure'
require 'fitgem/glucose'
require 'fitgem/heart_rate'
require 'fitgem/units'
require 'fitgem/foods'
require 'fitgem/friends'
require 'fitgem/body_measurements'
require 'fitgem/time_range'
require 'fitgem/devices'
require 'fitgem/notifications'
require 'fitgem/alarms'
require 'fitgem/badges'
require 'fitgem/locales'
require 'date'
require 'uri'

module Fitgem
  class Client
    API_VERSION = '1'
    EMPTY_BODY = ''

    # Sets or gets the api_version to be used in API calls
    #"
    # @return [String]
    attr_accessor :api_version

    # Sets or gets the api unit system to be used in API calls
    #
    # @return [String]
    #
    # @example Set this using the {Fitgem::ApiUnitSystem}
    #   client.api_unit_system = Fitgem::ApiUnitSystem.UK
    # @example May also be set in the constructor call
    #   client = Fitgem::Client {
    #     :consumer_key => my_key,
    #     :consumer_secret => my_secret,
    #     :token => fitbit_oauth_token,
    #     :unit_system => Fitgem::ApiUnitSystem.METRIC
    #   }
    attr_accessor :api_unit_system

    # Sets or gets the api locale to be used in API calls
    #
    # @return [String]
    #
    # @example Set this using the {Fitgem::ApiLocale}
    #   client.api_locale = Fitgem::ApiLocale.UK
    # @example May also be set in the constructor call
    #   client = Fitgem::Client {
    #     :consumer_key => my_key,
    #     :consumer_secret => my_secret,
    #     :token => fitbit_oauth_token,
    #     :unit_system => Fitgem::ApiUnitSystem.METRIC,
    #     :locale => Fitgem::ApiLocale.JP
    #   }
    attr_accessor :api_locale

    # Sets or gets the user id to be used in API calls
    #
    # @return [String]
    attr_accessor :user_id

    # Creates a client object to communicate with the fitbit API
    #
    # There are two primary ways to create a client: one if the current
    # fitbit user has not authenticated through fitbit.com, and another
    # if they have already authenticated and you have a stored
    # token returned by fitbit after the user authenticated and
    # authorized your application.
    #
    # @param [Hash] opts The constructor options
    # @option opts [String] :consumer_key The consumer key (required for
    #   OAuth)
    # @option opts [String] :consumer_secret The consumer secret (required
    #   for OAuth)
    # @option opts [String] :token The token generated by fitbit during the OAuth
    #   handshake; stored and re-passed to the constructor to create a
    #   'logged-in' client
    # @option opts [String] :user_id The Fitbit user id of the logged-in
    #   user
    # @option opts [Symbol] :unit_system The unit system to use for API
    #   calls; use {Fitgem::ApiUnitSystem} to set during initialization.
    #   DEFAULT: {Fitgem::ApiUnitSystem.US}
    # @option opts [Symbol] :locale The locale to use for API calls;
    #   use {Fitgem::ApiLocale} to set during initialization.
    #   DEFAULT: {Fitgem::ApiLocale.US}
    #
    # @example User has not yet authorized with fitbit
    #   client = Fitgem::Client.new { :consumer_key => my_key, :consumer_secret => my_secret }
    #
    # @example User has already authorized with fitbit, and we have a stored token
    #   client = Fitgem::Client.new {
    #     :consumer_key => my_key,
    #     :token => fitbit_oauth_token,
    #   }
    #
    # @return [Client] A Fitgem::Client; may be in a logged-in state or
    #   ready-to-login state
    def initialize(opts)
      missing = [:consumer_key, :consumer_secret] - opts.keys
      if missing.size > 0
        raise Fitgem::InvalidArgumentError, "Missing required options: #{missing.join(',')}"
      end
      @consumer_key = opts[:consumer_key]
      @consumer_secret = opts[:consumer_secret]

      @token = opts[:token]
      @user_id = opts[:user_id] || '-'

      @api_unit_system = opts[:unit_system] || Fitgem::ApiUnitSystem.US
      @api_version = API_VERSION
      @api_locale = opts[:locale] || Fitgem::ApiLocale.US
    end

    # Refresh access token
    #
    # @param [String] Refresh token
    # @return [OAuth2::AccessToken] Accesstoken and refresh token
    def refresh_access_token!(refresh_token)
      new_access_token = OAuth2::AccessToken.new(consumer, @token, refresh_token: refresh_token)
      # refresh! method return new object not itself and not change itself
      new_token = new_access_token.refresh!(headers: auth_header)
      @token = new_token.token
      @access_token = nil
      new_token
    end

    def expired?
      access_token.expired?
    end

    private

      def consumer
        @consumer ||= OAuth2::Client.new(@consumer_key, @consumer_secret, {
          :site          => 'https://api.fitbit.com',
          :token_url     => 'https://api.fitbit.com/oauth2/token',
          :authorize_url => 'https://www.fitbit.com/oauth2/authorize'
        })
      end

      def access_token
        @access_token ||= OAuth2::AccessToken.new(consumer, @token)
      end

      def get(path, headers={})
        extract_response_body raw_get(path, headers)
      end

      def raw_get(path, headers={})
        request(:get, path, headers: headers)
      end

      def post(path, body='', headers={})
        extract_response_body raw_post(path, body, headers)
      end

      def raw_post(path, body='', headers={})
        request(:post, path, body: body, headers: headers)
      end

      def delete(path, headers={})
        extract_response_body raw_delete(path, headers)
      end

      def raw_delete(path, headers={})
        request(:delete, path, headers: headers)
      end

      def request(verb, path, opts)
        versioned_path = "/#{@api_version}#{path}"
        opts.fetch(:headers) { {} }.merge! default_headers

        access_token.request(verb, versioned_path, opts)
      end

      def extract_response_body(response)
        return {} if response.nil?

        raise ServiceUnavailableError if response.status == 503

        return {} if response.body.nil?
        return {} if response.body.empty?

        JSON.parse(response.body)
      end

      def default_headers
        {
          'User-Agent' => "fitgem gem v#{Fitgem::VERSION}",
          'Accept-Language' => @api_unit_system,
          'Accept-Locale' => @api_locale
        }
      end

      def auth_header
        {Authorization: "Basic #{ Base64.encode64("#{ @consumer_key }:#{ @consumer_secret }") }" }
      end
  end
end
