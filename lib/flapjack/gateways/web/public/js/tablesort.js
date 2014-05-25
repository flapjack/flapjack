//
// Thanks to http://mottie.github.io/tablesorter/docs/example-widget-filter.html.
//
$(function() {

  $("table.tablesorter").tablesorter({

		headers: {
		  4: { sorter: 'customtime' },
		  5: { sorter: 'customtime' },
		  6: { sorter: 'customtime' }
		},
    widthFixed : false,
    widgets: ["filter"],
    widgetOptions : {
			filter_childRows : true,
      filter_columnFilters : true,
      filter_filteredRow   : 'filtered',
      filter_formatter : null,
      filter_functions : null,
      filter_hideFilters : true,
      filter_ignoreCase : true,
      filter_liveSearch : true,
      filter_reset : 'button.reset',
      filter_saveFilters : true,
      filter_searchDelay : 300,
      filter_serversideFiltering: false,
      filter_startsWith : false,
      filter_useParsedData : false
    }
  });

  $('button[data-filter-column]').click(function(){
    var filters = [],
      $t = $(this),
      col = $t.data('filter-column'),
      txt = $t.data('filter-text') || $t.text();

    filters[col] = txt;
    $.tablesorter.setFilters( $('table.hasFilters'), filters, true );
    return false;
  });

});
