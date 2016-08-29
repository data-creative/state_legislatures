require 'nokogiri'
require 'httparty'
require 'active_support/core_ext/object' # enable .try method

module Ncsl
  module GenderComposition
    class HtmlSource
      COLUMN_HEADERS = [
        {:html_header=> "State", :csv_header => "state"},
        {:html_header => "Number of Women Legislators in the House / Assembly", :csv_header => "house_women"},
        {:html_header => "Number of Women Legislators in the Senate", :csv_header => "senate_women"},
        {:html_header => "Total Number of Women Legislators", :csv_header => "total_women"},
        {:html_header => "Total Seats in the Legislature", :csv_header => "total_seats"},
        {:html_header => "Percentage of Women in the Legislature", :csv_header => "percentage_women"},
      ]
      HTML_COLUMN_HEADERS = COLUMN_HEADERS.map{|h| h[:html_header]}
      CSV_COLUMN_HEADERS = COLUMN_HEADERS.map{|h| h[:csv_header]}

      DATA_DIR = File.expand_path("../../../../data/gender_composition", __FILE__)

      def self.all
        Ncsl::GenderComposition::URL_SOURCES.map{|source| new(source) }
      end

      def initialize(source)
        @url = source[:url]
        @year = source[:year]
      end

      def html_path
        File.join(DATA_DIR, "html", "#{@year}.html")
      end

      def csv_path
        File.join(DATA_DIR, "csv", "#{@year}.csv")
      end

      def download
        unless File.exists?(html_path)
          puts "Extracting #{@year} data from #{@url}"
          response = HTTParty.get(@url) # HTTParty handles redirects
          puts "Writing to #{html_path}"
          File.open(html_path, "wb") do |file|
            file.write(response.body)
          end
        else
          puts "Detected local #{@year} data"
        end
      end

      def convert_to_csv
        puts "Parsing html"
        doc = File.open(html_path){|f| Nokogiri::HTML(f)}
        tables = doc.xpath("//table")
        table = tables.find{|table| table.attribute("summary").try(:value) == "State-by-state data about women in legislatures." }
        raise UnknownTableError unless table.present?

        rows = table.css("tr")
        puts "Found table with #{rows.count} rows"
        rows = rows.reject{|row| row.children.count == 1 } # exclude weird pre-header row ... #(Element:0x3fede1e81c8c { name = "tr", children = [ #(Text "\n\t\t")] })

        CSV.open(csv_path, "w") do |csv|
          csv << CSV_COLUMN_HEADERS
          rows.each_with_index do |row, i|
            tds = row.children.select{|child| child.name == "td" } # exclude erroneous Nokogiri::XML::Text elements
            next if tds.empty? # skip empty pre-header row
            raise UnexpectedCellCount unless tds.count == 6

            values = []
            tds.each do |td|
              if td.children.map{|child| child.name}.include?("div")
                div = td.children.find{|child| child.name == "div"}
                div_child_names = div.children.map{|child| child.name}
                if div_child_names.include?("b")
                  b = div.children.find{|child| child.name == "b"}
                  if b.children.count == 1
                    values << b.text.strip
                  else
                    binding.pry
                  end
                elsif div_child_names.include?("text")
                  if div.children.count == 1
                    values << div.text.strip
                  else
                    binding.pry
                  end
                end
              elsif td.children.count == 1
                values << td.text.strip
              else
                binding.pry
              end
            end
            puts "#{@year} -- #{i} -- #{values}"
            puts "... found header row" if values == HTML_COLUMN_HEADERS
            csv << values
          end
        end
      end

      class UnknownTableError < StandardError ; end
      class UnexpectedCellCount < StandardError ; end
    end
  end
end
