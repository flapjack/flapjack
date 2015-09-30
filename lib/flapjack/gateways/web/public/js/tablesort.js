//
// Thanks to http://mottie.github.io/tablesorter/docs/example-widget-filter.html.
//
$(function() {

  // Prepare the tablesorter pager container from the template
  var tableSorterPagerDiv = $("#tablesorter-pager");
  tableSorterPagerDiv.html($("#tablesorter-pager-template").html());

  $("table.tablesorter").tablesorter({

    headers: {
      4: {sorter: 'customtime'},
      5: {sorter: 'customtime'},
      6: {sorter: 'customtime'}
    },
    widthFixed: false,
    widgets: ["filter"],
    widgetOptions: {
      filter_childRows: true,
      filter_columnFilters: true,
      filter_filteredRow: 'filtered',
      filter_formatter: null,
      filter_functions: null,
      filter_hideFilters: true,
      filter_ignoreCase: true,
      filter_liveSearch: true,
      filter_reset: 'button.reset',
      filter_saveFilters: true,
      filter_searchDelay: 300,
      filter_serversideFiltering: false,
      filter_startsWith: false,
      filter_useParsedData: false
    }
  }).tablesorterPager({
    container: tableSorterPagerDiv,
    size: 50,
    output: '{startRow} to {endRow} of {filteredRows} rows (total {totalRows})'
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
