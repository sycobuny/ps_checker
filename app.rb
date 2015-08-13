#!/usr/bin/env ruby

$stdout.sync = true

require 'logger'
require 'bundler'
Bundler.setup   :default, :development
Bundler.require :default, :development

set :haml, :format => :html5

DB = Sequel.connect('postgres://localhost:5432/postgres')
DB.loggers << Logger.new($stdout)

def heredoc(str)
    str.gsub(/^ {8}/, '')
end

SQL = {
    ps_checker: heredoc(<<-SQL),
        SELECT results AS json
        FROM stats_json
    SQL
}

JS = {
    ps_checker: heredoc(<<-JS),
        function initializeChart() {
            options = {
                hAxis: {title: 'Time'},
                vAxis: {title: 'CPU %'}
            }

            chart = new google.visualization.LineChart(elem)
        }

        function drawChart(json) {
            var x, y

            initializeData()
            data.addColumn('datetime', 'X');

            $.each(json.columns, function(x, c) {
                data.addColumn('number', c)
            })

            data.addRows($.map(json.data, function(row) {
                var ret = [new Date(row[0])]
                for (var x = 1; x < row.length; x++) {
                    ret.push(parseFloat(row[x]))
                }

                return [ret]
            }))

            chart.draw(data, options)

            setTimeout(function() { $.getJSON(api, drawChart) }, 1000)
        }
    JS
}

TITLES = {
    ps_checker: 'PS Checker - Live System Stats',
}

get '/' do
    redirect '/ps_checker'
end

get %r{^/([a-z_]+)\.js$} do
    content_type :js
    JS[params['captures'].first.to_sym]
end

get %r{^/([a-z_]+)\.json$} do
    content_type :json
    DB[SQL[params['captures'].first.to_sym]].first[:json].to_s
end

get %r{^/([a-z_]+)$} do
    page = params['captures'].first.to_sym

    @title = TITLES[page]
    @js    = page
    @query = SQL[page]
    @code  = JS[page]

    haml :view
end

__END__

@@ view
!!!

%html{:lang => :en}
  %head
    %title= @title
    %script{:type => 'text/javascript', :src => 'https://www.google.com/jsapi'}
    %script{:type => 'text/javascript', :src => 'https://code.jquery.com/jquery-2.1.4.min.js'}
    %script{:type => 'text/javascript', :src => "/#{@js}.js"}
    %link{:rel => :stylesheet, :href => 'https://maxcdn.bootstrapcdn.com/bootstrap/3.3.5/css/bootstrap.min.css'}
    %link{:rel => :stylesheet, :href => 'http://getbootstrap.com/examples/cover/cover.css'}
    :css
        #chart {
            height: 400px;
            width:  100%;
        }

    :javascript
        var packages = ['corechart', 'line']
        google.load('visualization', '1', {packages: packages})

        var elem, data, options, chart, api

        function initializeData() {
            data = new google.visualization.DataTable()
        }

        $(function() {
            elem = document.getElementById('chart')
            api  = location.pathname + '.json'

            initializeData()
            initializeChart()
            $.getJSON(api, drawChart)
        })
  %body
    .site-wrapper
      .cover-container
        .inner.cover
          %h1.cover-heading= @title

          #chart

          %hr
          %pre.text-left= @query
          %hr
          %pre.text-left= @code
