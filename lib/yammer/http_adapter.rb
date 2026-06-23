# Copyright (c) Microsoft Corporation
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR 
# CONDITIONS OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING 
# WITHOUT LIMITATION ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE,
# FITNESS FOR A PARTICULAR PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT. 

# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.

require 'faraday'
require 'faraday/follow_redirects'
require 'faraday/multipart'
require 'logger'
require 'multi_json'
require 'addressable/uri'

module Yammer
class HttpAdapter

  class << self
    attr_accessor :log
  end

  attr_reader :site_url, :connection_options

  def initialize(site_url, opts={})
    unless site_url =~ /^https?/
      raise ArgumentError, "site_url must include either http or https scheme"
    end
    @site_url = site_url
    @connection_options = opts
  end

  # set the url to be used for creating an http connection
  # @param url [string]
  def site_url=(url)
    @site_url = url
    @host     = nil
    @scheme   = nil
  end

  def host
    @host ||= parsed_url.host
  end

  def scheme
    @scheme ||= parsed_url.scheme
  end

  def absolute_url(path='')
    "#{@site_url}#{path}"
  end

  def connection_options=(opts)
    raise ArgumentError, 'expected Hash' unless opts.is_a?(Hash)
    @connection_options = opts
  end

  def send_request(method, path, opts={})
    unless [:get, :delete, :post, :put].include?(method)
      raise "Unsupported HTTP method, #{method}"
    end

    params = opts.fetch(:params, {})
    response = connection.public_send(method, path) do |request|
      request.headers.update(opts.fetch(:headers, {}))
      request.options.timeout = connection_options[:timeout] if connection_options[:timeout]
      request.options.open_timeout = connection_options[:open_timeout] if connection_options[:open_timeout]

      if [:get, :delete].include?(method)
        request.params.update(params)
      else
        request.body = upload_params(params)
      end
    end

    Yammer::ApiResponse.new(response.headers, response.body, response.status)
  end

private
  def connection
    Faraday.new(url: site_url, ssl: { verify: connection_options.fetch(:verify_ssl, true) }) do |faraday|
      faraday.request :multipart
      faraday.request :url_encoded
      faraday.response :follow_redirects, limit: connection_options.fetch(:max_redirects, 5)
      faraday.response :logger, logger if self.class.log
    end
  end

  def upload_params(params)
    params.each_with_object({}) do |(key, value), result|
      result[key] = if value.respond_to?(:read) && value.respond_to?(:path)
                      Faraday::UploadIO.new(value, 'application/octet-stream', File.basename(value.path))
                    else
                      value
                    end
    end
  end

  def logger
    return self.class.log if self.class.log.respond_to?(:info)

    output = self.class.log == 'stdout' ? $stdout : self.class.log
    output = $stderr if self.class.log == 'stderr'
    Logger.new(output)
  end

  def parsed_url
    Addressable::URI.parse(@site_url)
  end

end
end
