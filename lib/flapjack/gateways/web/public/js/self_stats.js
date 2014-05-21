$(document).ready(function() {

  /* Done setting the chart up? Time to render it!*/
  var data = [
    {
      values: [],
      key: 'Event queue length',
      color: '#000000'
    },
  ]

  /*These lines are all chart setup.  Pick and choose which chart features you want to utilize. */
  nv.addGraph(function() {
    var chart = nv.models.lineChart()
                  .margin({right: 80})  //Adjust chart margins to give the x-axis some breathing room.
                  .useInteractiveGuideline(true)  //We want nice looking tooltips and a guideline!
                  .transitionDuration(350)  //how fast do you want the lines to transition?
                  .showLegend(false)       //Show the legend, allowing users to turn on/off line series.
                  .showYAxis(true)        //Show the y-axis
                  .showXAxis(true)        //Show the x-axis
                  .noData("Waiting for queue length data...")
    ;

    // Chart x-axis settings
    chart.xAxis
        .tickPadding(9)
        .tickFormat(function(d) {
            return d3.time.format('%H:%M:%S')(new Date(d))
        });

    // Chart y-axis settings
    chart.yAxis
        .tickPadding(7)
        .tickFormat(d3.format(',d'));

    d3.select('#chart svg')
        .datum(data)
        .call(chart);

    // Poll every 5 seconds
    setInterval(function() {
        updateData()

        d3.select('#chart svg')
            .datum(data)
            .transition();

        d3.select("#chart svg rect")
            .style("opacity", 1)
            .style("fill", '#fff')

        chart.update()
    }, 5000);

    // Update the chart when window resizes.
    nv.utils.windowResize(function() { chart.update() });
    return chart;
  });

  function updateData() {
    var api_url = $('div#data-api-url').data('api-url');
    $.get(api_url + '/metrics?filter=event_queue_length', function(json) {
      var d = new Date().getTime();
      var value = {x: d, y: json.event_queue_length}
      data[0].values.push(value)

      // Remove old data, to keep the graph performant
      if (data[0].values.length > 100) {
        data[0].values.shift()
      }
    }, 'json')
  }

});
