#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Reads queue.json and executes each command against monday.com.
# Successfully processed items are removed from the queue.

require "json"
require "net/http"
require "uri"
require "dotenv/load"

QUEUE_FILE = "queue.json"
TOKEN  = ENV.fetch("MONDAY_API_TOKEN")
BOARD  = ENV.fetch("DEFAULT_BOARD_ID").to_i

abort "Empty queue." if File.read(QUEUE_FILE).strip.empty?

queue = JSON.parse(File.read(QUEUE_FILE))
abort "Nothing to process." if queue.empty?

def graphql(query:, variables: {})
  uri  = URI("https://api.monday.com/v2")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  req = Net::HTTP::Post.new(uri)
  req["Authorization"] = TOKEN
  req.content_type = "application/json"
  req.body = { query:, variables: }.to_json
  res = http.request(req)
  JSON.parse(res.body)
end

processed = []
queue.each do |item|
  case item["command"]
  when "create_task"
    col_vals = {
      status: { label: item["status"] },
      date4:  { date: item["due-date"] } # 'date4' = “Due Date” column ID example
    }
    query = <<~GRAPHQL
      mutation ($board:Int!, $name:String!, $cols:JSON!) {
        create_item (board_id:$board, item_name:$name, column_values:$cols) {
          id
        }
      }
    GRAPHQL
    resp = graphql(query:, variables: { board: BOARD, name: item["task"], cols: col_vals.to_json })
    if resp["data"]
      puts "✅ Created item #{resp.dig("data", "create_item", "id")}"
      processed << item
    else
      warn "❌ Error: #{resp}"
    end
  else
    warn "⚠️  Unknown command: #{item}"
  end
end

# remove processed items
if processed.any?
  queue -= processed
  File.write(QUEUE_FILE, JSON.pretty_generate(queue))
end
