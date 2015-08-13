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
    raw_table: heredoc(<<-SQL),
        SELECT TO_JSON(ARRAY_AGG(ROW_TO_JSON(p))) AS json
        FROM participants AS p
    SQL

    age_brackets: heredoc(<<-SQL),
        SELECT TO_JSON(ARRAY_AGG(ROW_TO_JSON(data))) AS json
        FROM (
            SELECT
                COUNT(*),
                TRUNC(EXTRACT(YEAR FROM AGE(birthday)) / 10) * 10 AS bracket
            FROM participants
            GROUP BY 2
        ) AS data
    SQL

    gendered_brackets: heredoc(<<-SQL),
        WITH
        data AS (
            SELECT
                COUNT(*),
                (TRUNC(EXTRACT(YEAR FROM AGE(birthday)) / 10) * 10)::text || 's' AS age,
                gender
            FROM participants
            GROUP BY 2, 3
        ),
        data_table AS (
            SELECT DISTINCT ON (data.age) JSON_BUILD_ARRAY(
                data.age,
                (SELECT count FROM data d WHERE d.gender = 'M'   AND d.age = data.age),
                (SELECT count FROM data d WHERE d.gender = 'F'   AND d.age = data.age),
                (SELECT count FROM data d WHERE d.gender = 'O'   AND d.age = data.age),
                (SELECT count FROM data d WHERE d.gender IS NULL AND d.age = data.age)
            )
            FROM data
            ORDER BY data.age
        )

        SELECT TO_JSON(ARRAY_AGG(json_build_array)) AS json FROM data_table;
    SQL

    ps_checker: heredoc(<<-SQL),
        SELECT results AS json
        FROM stats_json
    SQL
}

JS = {
    raw_table: heredoc(<<-JS),
        function initializeChart() {
            options = {showRowNumber: false, width: '100%'}

            data.addColumn('number', 'DB ID')
            data.addColumn('string', 'ID Code')
            data.addColumn('date',   'Birthday')
            data.addColumn('string', 'Gender')

            chart = new google.visualization.Table(elem)
        }

        function drawChart(json) {
            json = $.map(json, function(row) {return [[
                row.id, row.code, new Date(row.birthday), row.gender
            ]]})

            data.addRows(json)
            chart.draw(data, options)
        }
    JS

    age_brackets: heredoc(<<-JS),
        function initializeChart() {
            options = {is3D:  true, title: 'Participants by Age Group'}

            data.addColumn('string', 'Bracket')
            data.addColumn('number', 'Count')

            chart = new google.visualization.PieChart(elem)
        }

        function drawChart(json) {
            data.addRows($.map(json, function(row) {return [[
                row.bracket + 's', row.count
            ]]}))

            chart.draw(data, options)
        }
    JS

    gendered_brackets: heredoc(<<-JS),
        function initializeChart() {
            options = {
                title:  'Participants by Age Group and Gender',
                colors: ['#9575cd', '#33ac71', '#f00', '#0f0'],
                hAxis:  {title: 'Age Group'},
                vAxis:  {title: 'Count'}
            }

            data.addColumn('string', 'Age Bracket')
            data.addColumn('number', 'Males')
            data.addColumn('number', 'Females')
            data.addColumn('number', 'Other')
            data.addColumn('number', '\u2205')

            chart = new google.visualization.ColumnChart(elem)
        }

        function drawChart(json) {
            data.addRows(json)
            chart.draw(data, options)
        }
    JS

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
    raw_table:         'Example Participant Data',
    age_brackets:      'Parsed Data',
    gendered_brackets: 'Broken Down by Age + Gender',
    ps_checker:        'PS Checker - Live System Stats',
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
        body { color: #000 }
        h1   { color: #fff }
        #chart {
            height: 400px;
            width:  100%;
        }

    :javascript
        var packages = ['table', 'bar', 'corechart', 'line']
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
