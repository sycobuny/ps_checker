#!/usr/bin/env ruby

require 'bundler'
Bundler.setup   :default, :development
Bundler.require :default, :development

set :haml, :format => :html5

DB = Sequel.connect('postgres://localhost:5432/postgres')

get '/' do
    haml :view
end

get '/stats.json' do
    content_type :json
    DB[:stats_json].first[:results].to_s
end

__END__

@@ view
!!!

%html{:lang => :en}
  %head
    %title PS Checker - Current Stats
    %script{:type => 'text/javascript', :src => 'https://www.google.com/jsapi'}
    %script{:type => 'text/javascript', :src => 'https://code.jquery.com/jquery-2.1.4.min.js'}
    %link{:rel => :stylesheet, :href => 'https://maxcdn.bootstrapcdn.com/bootstrap/3.3.5/css/bootstrap.min.css'}
    %link{:rel => :stylesheet, :href => 'http://getbootstrap.com/examples/cover/cover.css'}
  %body
    .site-wrapper
      .cover-container
        .inner.cover
          %h1.cover-heading PS Checker - Current Stats

          #chart

    :javascript
        google.load('visualization', '1', {packages: ['corechart', 'line']})

        function drawChart(json) {
            var data, x, y, options, elem, chart

            data = new google.visualization.DataTable()
            data.addColumn('datetime', 'X');
            for (x = 0; x < json.columns.length; x++) {
                data.addColumn('number', json.columns[x])
            }

            for (x = 0; x < json.data.length; x++) {
                json.data[x][0] = new Date(json.data[x][0])
                for (y = 1; y < json.data[x].length; y++) {
                    json.data[x][y] = parseFloat(json.data[x][y]);
                }
            }

            data.addRows(json.data)

            options = {
                hAxis: {title: 'Time'},
                vAxis: {title: 'CPU %'},
                series: {
                    1: {curveType: 'function'}
                }
            }

            elem  = document.getElementById('chart')
            chart = new google.visualization.LineChart(elem)

            chart.draw(data, options)
        }

        $(function() {
            setInterval(function() {
                $.getJSON('/stats.json', drawChart)
            }, 1000)
        })
