#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
gem "fastlane", "= 2.226.0"
require "spaceship"
require "time"
require "uri"

def required(name)
  value = ENV.fetch(name, "").strip
  raise "#{name} is required" if value.empty?

  value
end

def get_json(path, query, token)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  uri.query = URI.encode_www_form(query)
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{token}"
  request["Accept"] = "application/json"
  response = Net::HTTP.start(
    uri.hostname,
    uri.port,
    use_ssl: true,
    open_timeout: 20,
    read_timeout: 30
  ) { |http| http.request(request) }
  unless response.is_a?(Net::HTTPSuccess)
    error = JSON.parse(response.body) rescue {}
    details = Array(error["errors"]).filter_map do |item|
      next unless item.is_a?(Hash)

      [item["status"], item["code"], item["title"], item["detail"]]
        .compact.join(" ")[0, 600]
    end
    raise "App Store Connect returned #{response.code}: #{details.join("; ")}"
  end

  JSON.parse(response.body)
end

def resources(response)
  data = response.fetch("data")
  raise "App Store Connect returned a non-list response" unless data.is_a?(Array)

  data
end

def state_details(state)
  return [] unless state.is_a?(Hash)

  %w[errors warnings infos].flat_map do |kind|
    Array(state[kind]).filter_map do |item|
      next unless item.is_a?(Hash)

      value = {
        "kind" => kind.delete_suffix("s"),
        "code" => item["code"],
        "description" => item["description"] || item["message"]
      }.compact
      value unless value.empty?
    end
  end.first(20)
end

def upload_summary(resource)
  attributes = resource.fetch("attributes", {})
  state = attributes["state"]
  state_value = state.is_a?(Hash) ? state["state"] : state
  {
    "state" => state_value,
    "created_date" => attributes["createdDate"],
    "uploaded_date" => attributes["uploadedDate"],
    "details" => state_details(state)
  }
end

def build_summary(resource)
  attributes = resource.fetch("attributes", {})
  {
    "processing_state" => attributes["processingState"],
    "uploaded_date" => attributes["uploadedDate"],
    "audience" => attributes["buildAudienceType"],
    "expired" => attributes["expired"]
  }
end

bundle_id = required("IOS_BUNDLE_ID")
build_name = required("BUILD_NAME")
build_number = required("BUILD_NUMBER")
key_path = required("APP_STORE_CONNECT_KEY_PATH")

token = Spaceship::ConnectAPI::Token.create(
  key_id: required("APPLE_API_KEY_ID"),
  issuer_id: required("APPLE_ISSUER_ID"),
  filepath: key_path,
  duration: 600,
  in_house: false
).text

apps = resources(get_json(
  "/v1/apps",
  { "filter[bundleId]" => bundle_id, "limit" => "2" },
  token
))
raise "expected exactly one App Store Connect app for #{bundle_id}" unless apps.length == 1

app_id = apps.first.fetch("id")
uploads = resources(get_json(
  "/v1/apps/#{URI.encode_www_form_component(app_id)}/buildUploads",
  {
    "filter[cfBundleShortVersionString]" => build_name,
    "filter[cfBundleVersion]" => build_number,
    "filter[platform]" => "IOS",
    "sort" => "-uploadedDate",
    "limit" => "10"
  },
  token
))
builds = resources(get_json(
  "/v1/builds",
  {
    "filter[app]" => app_id,
    "filter[version]" => build_number,
    "filter[preReleaseVersion.version]" => build_name,
    "filter[preReleaseVersion.platform]" => "IOS",
    "sort" => "-uploadedDate",
    "limit" => "10"
  },
  token
))

upload = uploads.first && upload_summary(uploads.first)
build = builds.first && build_summary(builds.first)
build_state = build && build["processing_state"]
upload_state = upload && upload["state"]
outcome = if build_state == "VALID"
            "valid"
          elsif %w[FAILED INVALID].include?(build_state) || upload_state == "FAILED"
            "failed"
          elsif build || upload
            "processing"
          else
            "missing"
          end

puts JSON.generate({
  "bundle_id" => bundle_id,
  "build_name" => build_name,
  "build_number" => build_number,
  "observed_at" => Time.now.utc.iso8601,
  "outcome" => outcome,
  "upload" => upload,
  "build" => build
})
