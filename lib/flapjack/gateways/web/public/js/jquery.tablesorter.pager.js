/*!
 * tablesorter pager plugin
 * updated 9/15/2014 (v2.17.8)
 */
/*jshint browser:true, jquery:true, unused:false */
;(function($) {
	"use strict";
	/*jshint supernew:true */
	var ts = $.tablesorter;

	$.extend({ tablesorterPager: new function() {

		this.defaults = {
			// target the pager markup
			container: null,

			// use this format: "http://mydatabase.com?page={page}&size={size}&{sortList:col}&{filterList:fcol}"
			// where {page} is replaced by the page number, {size} is replaced by the number of records to show,
			// {sortList:col} adds the sortList to the url into a "col" array, and {filterList:fcol} adds
			// the filterList to the url into an "fcol" array.
			// So a sortList = [[2,0],[3,0]] becomes "&col[2]=0&col[3]=0" in the url
			// and a filterList = [[2,Blue],[3,13]] becomes "&fcol[2]=Blue&fcol[3]=13" in the url
			ajaxUrl: null,

			// modify the url after all processing has been applied
			customAjaxUrl: function(table, url) { return url; },

			// modify the $.ajax object to allow complete control over your ajax requests
			ajaxObject: {
				dataType: 'json'
			},

			// set this to false if you want to block ajax loading on init
			processAjaxOnInit: true,

			// process ajax so that the following information is returned:
			// [ total_rows (number), rows (array of arrays), headers (array; optional) ]
			// example:
			// [
			//   100,  // total rows
			//   [
			//     [ "row1cell1", "row1cell2", ... "row1cellN" ],
			//     [ "row2cell1", "row2cell2", ... "row2cellN" ],
			//     ...
			//     [ "rowNcell1", "rowNcell2", ... "rowNcellN" ]
			//   ],
			//   [ "header1", "header2", ... "headerN" ] // optional
			// ]
			ajaxProcessing: function(ajax){ return [ 0, [], null ]; },

			// output default: '{page}/{totalPages}'
			// possible variables: {page}, {totalPages}, {filteredPages}, {startRow}, {endRow}, {filteredRows} and {totalRows}
			output: '{startRow} to {endRow} of {totalRows} rows', // '{page}/{totalPages}'

			// apply disabled classname to the pager arrows when the rows at either extreme is visible
			updateArrows: true,

			// starting page of the pager (zero based index)
			page: 0,

		// reset pager after filtering; set to desired page #
		// set to false to not change page at filter start
			pageReset: 0,

			// Number of visible rows
			size: 10,

			// Save pager page & size if the storage script is loaded (requires $.tablesorter.storage in jquery.tablesorter.widgets.js)
			savePages: true,

			// defines custom storage key
			storageKey: 'tablesorter-pager',

			// if true, the table will remain the same height no matter how many records are displayed. The space is made up by an empty
			// table row set to a height to compensate; default is false
			fixedHeight: false,

			// count child rows towards the set page size? (set true if it is a visible table row within the pager)
			// if true, child row(s) may not appear to be attached to its parent row, may be split across pages or
			// may distort the table if rowspan or cellspans are included.
			countChildRows: false,

			// remove rows from the table to speed up the sort of large tables.
			// setting this to false, only hides the non-visible rows; needed if you plan to add/remove rows with the pager enabled.
			removeRows: false, // removing rows in larger tables speeds up the sort

			// css class names of pager arrows
			cssFirst: '.first', // go to first page arrow
			cssPrev: '.prev', // previous page arrow
			cssNext: '.next', // next page arrow
			cssLast: '.last', // go to last page arrow
			cssGoto: '.gotoPage', // go to page selector - select dropdown that sets the current page
			cssPageDisplay: '.pagedisplay', // location of where the "output" is displayed
			cssPageSize: '.pagesize', // page size selector - select dropdown that sets the "size" option
			cssErrorRow: 'tablesorter-errorRow', // error information row

			// class added to arrows when at the extremes (i.e. prev/first arrows are "disabled" when on the first page)
			cssDisabled: 'disabled', // Note there is no period "." in front of this class name

			// stuff not set by the user
			totalRows: 0,
			totalPages: 0,
			filteredRows: 0,
			filteredPages: 0,
			ajaxCounter: 0,
			currentFilters: [],
			startRow: 0,
			endRow: 0,
			$size: null,
			last: {}

		};

		var $this = this,

		// hide arrows at extremes
		pagerArrows = function(p, disable) {
			var a = 'addClass',
			r = 'removeClass',
			d = p.cssDisabled,
			dis = !!disable,
			first = ( dis || p.page === 0 ),
			tp = Math.min( p.totalPages, p.filteredPages ),
			last = ( dis || (p.page === tp - 1) || tp === 0 );
			if ( p.updateArrows ) {
				p.$container.find(p.cssFirst + ',' + p.cssPrev)[ first ? a : r ](d).attr('aria-disabled', first);
				p.$container.find(p.cssNext + ',' + p.cssLast)[ last ? a : r ](d).attr('aria-disabled', last);
			}
		},

		updatePageDisplay = function(table, p, completed) {
			var i, pg, s, $out, regex,
				c = table.config,
				f = c.$table.hasClass('hasFilters'),
				t = [],
				sz = p.size || 10; // don't allow dividing by zero
			t = [ (c.widgetOptions && c.widgetOptions.filter_filteredRow || 'filtered'), c.selectorRemove.replace(/^(\w+\.)/g,'') ];
			if (p.countChildRows) { t.push(c.cssChildRow); }
			regex = new RegExp( '(' + t.join('|') + ')' );
			if (f && !p.ajaxUrl) {
				if ($.isEmptyObject(c.cache)) {
					// delayInit: true so nothing is in the cache
					p.filteredRows = p.totalRows = c.$tbodies.eq(0).children('tr').not( p.countChildRows ? '' : '.' + c.cssChildRow ).length;
				} else {
					p.filteredRows = 0;
					$.each(c.cache[0].normalized, function(i, el) {
						p.filteredRows += p.regexRows.test(el[c.columns].$row[0].className) ? 0 : 1;
					});
				}
			} else if (!f) {
				p.filteredRows = p.totalRows;
			}
			p.totalPages = Math.ceil( p.totalRows / sz ); // needed for "pageSize" method
			c.totalRows = p.totalRows;
			c.filteredRows = p.filteredRows;
			p.filteredPages = Math.ceil( p.filteredRows / sz ) || 0;
			if ( Math.min( p.totalPages, p.filteredPages ) >= 0 ) {
				t = (p.size * p.page > p.filteredRows);
				p.startRow = (t) ? 1 : (p.filteredRows === 0 ? 0 : p.size * p.page + 1);
				p.page = (t) ? 0 : p.page;
				p.endRow = Math.min( p.filteredRows, p.totalRows, p.size * ( p.page + 1 ) );
				$out = p.$container.find(p.cssPageDisplay);
				// form the output string (can now get a new output string from the server)
				s = ( p.ajaxData && p.ajaxData.output ? p.ajaxData.output || p.output : p.output )
					// {page} = one-based index; {page+#} = zero based index +/- value
					.replace(/\{page([\-+]\d+)?\}/gi, function(m,n){
						return p.totalPages ? p.page + (n ? parseInt(n, 10) : 1) : 0;
					})
					// {totalPages}, {extra}, {extra:0} (array) or {extra : key} (object)
					.replace(/\{\w+(\s*:\s*\w+)?\}/gi, function(m){
						var len, indx,
							str = m.replace(/[{}\s]/g,''),
							extra = str.split(':'),
							data = p.ajaxData,
							// return zero for default page/row numbers
							deflt = /(rows?|pages?)$/i.test(str) ? 0 : '';
						if (/(startRow|page)/.test(extra[0]) && extra[1] === 'input') {
							len = ('' + (extra[0] === 'page' ? p.totalPages : p.totalRows)).length;
							indx = extra[0] === 'page' ? p.page + 1 : p.startRow;
							return '<input type="text" class="ts-' + extra[0] + '" style="max-width:' + len + 'em" value="' + indx + '"/>';
						}
						return extra.length > 1 && data && data[extra[0]] ? data[extra[0]][extra[1]] : p[str] || (data ? data[str] : deflt) || deflt;
					});
				if ($out.length) {
					$out[ ($out[0].tagName === 'INPUT') ? 'val' : 'html' ](s);
					if ( p.$goto.length ) {
						t = '';
						pg = Math.min( p.totalPages, p.filteredPages );
						for ( i = 1; i <= pg; i++ ) {
							t += '<option>' + i + '</option>';
						}
						p.$goto[0].innerHTML = t;
						p.$goto[0].value = p.page + 1;
					}
					// rebind startRow/page inputs
					$out.find('.ts-startRow, .ts-page').unbind('change').bind('change', function(){
						var v = $(this).val(),
							pg = $(this).hasClass('ts-startRow') ? Math.floor( v/p.size ) + 1 : v;
						c.$table.trigger('pageSet.pager', [ pg ]);
					});
				}
			}
			pagerArrows(p);
			if (p.initialized && completed !== false) {
				c.$table.trigger('pagerComplete', p);
				// save pager info to storage
				if (p.savePages && ts.storage) {
					ts.storage(table, p.storageKey, {
						page : p.page,
						size : p.size
					});
				}
			}
		},

		fixHeight = function(table, p) {
			var d, h,
				c = table.config,
				$b = c.$tbodies.eq(0);
			if (p.fixedHeight) {
				$b.find('tr.pagerSavedHeightSpacer').remove();
				h = $.data(table, 'pagerSavedHeight');
				if (h) {
					d = h - $b.height();
					if ( d > 5 && $.data(table, 'pagerLastSize') === p.size && $b.children('tr:visible').length < p.size ) {
						$b.append('<tr class="pagerSavedHeightSpacer ' + c.selectorRemove.replace(/^(\w+\.)/g,'') + '" style="height:' + d + 'px;"></tr>');
					}
				}
			}
		},

		changeHeight = function(table, p) {
			var $b = table.config.$tbodies.eq(0);
			$b.find('tr.pagerSavedHeightSpacer').remove();
			$.data(table, 'pagerSavedHeight', $b.height());
			fixHeight(table, p);
			$.data(table, 'pagerLastSize', p.size);
		},

		hideRows = function(table, p){
			if (!p.ajaxUrl) {
				var i,
				lastIndex = 0,
				c = table.config,
				rows = c.$tbodies.eq(0).children('tr'),
				l = rows.length,
				s = ( p.page * p.size ),
				e =  s + p.size,
				f = c.widgetOptions && c.widgetOptions.filter_filteredRow || 'filtered',
				j = 0; // size counter
				for ( i = 0; i < l; i++ ){
					if ( !rows[i].className.match(f) ) {
						if (j === s && rows[i].className.match(c.cssChildRow)) {
							// hide child rows @ start of pager (if already visible)
							rows[i].style.display = 'none';
						} else {
							rows[i].style.display = ( j >= s && j < e ) ? '' : 'none';
							// don't count child rows
							j += rows[i].className.match(c.cssChildRow + '|' + c.selectorRemove.replace(/^(\w+\.)/g,'')) && !p.countChildRows ? 0 : 1;
							if ( j === e && rows[i].style.display !== 'none' && rows[i].className.match(ts.css.cssHasChild) ) {
								lastIndex = i;
							}
						}
					}
				}
				// add any attached child rows to last row of pager. Fixes part of issue #396
				if ( lastIndex > 0 && rows[lastIndex].className.match(ts.css.cssHasChild) ) {
					while ( ++lastIndex < l && rows[lastIndex].className.match(c.cssChildRow) ) {
						rows[lastIndex].style.display = '';
					}
				}
			}
		},

		hideRowsSetup = function(table, p){
			p.size = parseInt( p.$size.val(), 10 ) || p.size;
			$.data(table, 'pagerLastSize', p.size);
			pagerArrows(p);
			if ( !p.removeRows ) {
				hideRows(table, p);
				$(table).bind('sortEnd.pager filterEnd.pager', function(){
					hideRows(table, p);
				});
			}
		},

		renderAjax = function(data, table, p, xhr, exception){
			// process data
			if ( typeof(p.ajaxProcessing) === "function" ) {
				// ajaxProcessing result: [ total, rows, headers ]
				var i, j, hsh, $f, $sh, t, th, d, l, rr_count,
					c = table.config,
					$t = c.$table,
					tds = '',
					result = p.ajaxProcessing(data, table, xhr) || [ 0, [] ],
					hl = $t.find('thead th').length;

				// Clean up any previous error.
				ts.showError(table);

				if ( exception ) {
					if (c.debug) {
						ts.log('Ajax Error', xhr, exception);
					}
					ts.showError(table,
						xhr.status === 0 ? 'Not connected, verify Network' :
						xhr.status === 404 ? 'Requested page not found [404]' :
						xhr.status === 500 ? 'Internal Server Error [500]' :
						exception === 'parsererror' ? 'Requested JSON parse failed' :
						exception === 'timeout' ? 'Time out error' :
						exception === 'abort' ? 'Ajax Request aborted' :
						'Uncaught error: ' + xhr.statusText + ' [' + xhr.status + ']' );
					c.$tbodies.eq(0).children('tr').detach();
					p.totalRows = 0;
				} else {
					// process ajax object
					if (!$.isArray(result)) {
						p.ajaxData = result;
						c.totalRows = p.totalRows = result.total;
						c.filteredRows = p.filteredRows = typeof result.filteredRows !== 'undefined' ? result.filteredRows : result.total;
						th = result.headers;
						d = result.rows;
					} else {
						// allow [ total, rows, headers ]  or [ rows, total, headers ]
						t = isNaN(result[0]) && !isNaN(result[1]);
						// ensure a zero returned row count doesn't fail the logical ||
						rr_count = result[t ? 1 : 0];
						p.totalRows = isNaN(rr_count) ? p.totalRows || 0 : rr_count;
						// can't set filtered rows when returning an array
						c.totalRows = c.filteredRows = p.filteredRows = p.totalRows;
						d = p.totalRows === 0 ? [""] : result[t ? 0 : 1] || []; // row data
						th = result[2]; // headers
					}
					l = d && d.length;
					if (d instanceof jQuery) {
						if (p.processAjaxOnInit) {
							// append jQuery object
							c.$tbodies.eq(0).children('tr').detach();
							c.$tbodies.eq(0).append(d);
						}
					} else if (l) {
						// build table from array
						for ( i = 0; i < l; i++ ) {
							tds += '<tr>';
							for ( j = 0; j < d[i].length; j++ ) {
								// build tbody cells; watch for data containing HTML markup - see #434
								tds += /^\s*<td/.test(d[i][j]) ? $.trim(d[i][j]) : '<td>' + d[i][j] + '</td>';
							}
							tds += '</tr>';
						}
						// add rows to first tbody
						if (p.processAjaxOnInit) {
							c.$tbodies.eq(0).html( tds );
						}
					}
					p.processAjaxOnInit = true;
					// only add new header text if the length matches
					if ( th && th.length === hl ) {
						hsh = $t.hasClass('hasStickyHeaders');
						$sh = hsh ? c.widgetOptions.$sticky.children('thead:first').children('tr').children() : '';
						$f = $t.find('tfoot tr:first').children();
						// don't change td headers (may contain pager)
						c.$headers.filter('th').each(function(j){
							var $t = $(this), icn;
							// add new test within the first span it finds, or just in the header
							if ( $t.find('.' + ts.css.icon).length ) {
								icn = $t.find('.' + ts.css.icon).clone(true);
								$t.find('.tablesorter-header-inner').html( th[j] ).append(icn);
								if ( hsh && $sh.length ) {
									icn = $sh.eq(j).find('.' + ts.css.icon).clone(true);
									$sh.eq(j).find('.tablesorter-header-inner').html( th[j] ).append(icn);
								}
							} else {
								$t.find('.tablesorter-header-inner').html( th[j] );
								if (hsh && $sh.length) {
									$sh.eq(j).find('.tablesorter-header-inner').html( th[j] );
								}
							}
							$f.eq(j).html( th[j] );
						});
					}
				}
				if (c.showProcessing) {
					ts.isProcessing(table); // remove loading icon
				}
				// make sure last pager settings are saved, prevents multiple server side calls with
				// the same parameters
				p.totalPages = Math.ceil( p.totalRows / ( p.size || 10 ) );
				p.last.totalRows = p.totalRows;
				p.last.currentFilters = p.currentFilters;
				p.last.sortList = (c.sortList || []).join(',');
				updatePageDisplay(table, p);
				fixHeight(table, p);
				$t.trigger('updateCache', [function(){
					if (p.initialized) {
						// apply widgets after table has rendered & after a delay to prevent
						// multiple applyWidget blocking code from blocking this trigger
						setTimeout(function(){
							$t
								.trigger('applyWidgets')
								.trigger('pagerChange', p);
							}, 0);
					}
				}]);

			}
			if (!p.initialized) {
				p.initialized = true;
				$(table)
					.trigger('applyWidgets')
					.trigger('pagerInitialized', p);
			}
		},

		getAjax = function(table, p){
			var url = getAjaxUrl(table, p),
			$doc = $(document),
			counter,
			c = table.config;
			if ( url !== '' ) {
				if (c.showProcessing) {
					ts.isProcessing(table, true); // show loading icon
				}
				$doc.bind('ajaxError.pager', function(e, xhr, settings, exception) {
					renderAjax(null, table, p, xhr, exception);
					$doc.unbind('ajaxError.pager');
				});

				counter = ++p.ajaxCounter;

				p.ajaxObject.url = url; // from the ajaxUrl option and modified by customAjaxUrl
				p.ajaxObject.success = function(data, status, jqxhr) {
					// Refuse to process old ajax commands that were overwritten by new ones - see #443
					if (counter < p.ajaxCounter){
						return;
					}
					renderAjax(data, table, p, jqxhr);
					$doc.unbind('ajaxError.pager');
					if (typeof p.oldAjaxSuccess === 'function') {
						p.oldAjaxSuccess(data);
					}
				};
				if (c.debug) {
					ts.log('ajax initialized', p.ajaxObject);
				}
				$.ajax(p.ajaxObject);
			}
		},

		getAjaxUrl = function(table, p) {
			var c = table.config,
				url = (p.ajaxUrl) ? p.ajaxUrl
				// allow using "{page+1}" in the url string to switch to a non-zero based index
				.replace(/\{page([\-+]\d+)?\}/, function(s,n){ return p.page + (n ? parseInt(n, 10) : 0); })
				.replace(/\{size\}/g, p.size) : '',
			sl = c.sortList,
			fl = p.currentFilters || $(table).data('lastSearch') || [],
			sortCol = url.match(/\{\s*sort(?:List)?\s*:\s*(\w*)\s*\}/),
			filterCol = url.match(/\{\s*filter(?:List)?\s*:\s*(\w*)\s*\}/),
			arry = [];
			if (sortCol) {
				sortCol = sortCol[1];
				$.each(sl, function(i,v){
					arry.push(sortCol + '[' + v[0] + ']=' + v[1]);
				});
				// if the arry is empty, just add the col parameter... "&{sortList:col}" becomes "&col"
				url = url.replace(/\{\s*sort(?:List)?\s*:\s*(\w*)\s*\}/g, arry.length ? arry.join('&') : sortCol );
				arry = [];
			}
			if (filterCol) {
				filterCol = filterCol[1];
				$.each(fl, function(i,v){
					if (v) {
						arry.push(filterCol + '[' + i + ']=' + encodeURIComponent(v));
					}
				});
				// if the arry is empty, just add the fcol parameter... "&{filterList:fcol}" becomes "&fcol"
				url = url.replace(/\{\s*filter(?:List)?\s*:\s*(\w*)\s*\}/g, arry.length ? arry.join('&') : filterCol );
				p.currentFilters = fl;
			}
			if ( typeof(p.customAjaxUrl) === "function" ) {
				url = p.customAjaxUrl(table, url);
			}
			if (c.debug) {
				ts.log('Pager ajax url: ' + url);
			}
			return url;
		},

		renderTable = function(table, rows, p) {
			var $tb, index, count, added,
				$t = $(table),
				c = table.config,
				f = c.$table.hasClass('hasFilters'),
				l = rows && rows.length || 0, // rows may be undefined
				s = ( p.page * p.size ),
				e = p.size;
			if ( l < 1 ) {
				if (c.debug) {
					ts.log('Pager: no rows for pager to render');
				}
				// empty table, abort!
				return;
			}
			if ( p.page >= p.totalPages ) {
				// lets not render the table more than once
				moveToLastPage(table, p);
			}
			p.isDisabled = false; // needed because sorting will change the page and re-enable the pager
			if (p.initialized) { $t.trigger('pagerChange', p); }

			if ( !p.removeRows ) {
				hideRows(table, p);
			} else {
				ts.clearTableBody(table);
				$tb = ts.processTbody(table, c.$tbodies.eq(0), true);
				// not filtered, start from the calculated starting point (s)
				// if filtered, start from zero
				index = f ? 0 : s;
				count = f ? 0 : s;
				added = 0;
				while (added < e && index < rows.length) {
					if (!f || !/filtered/.test(rows[index][0].className)){
						count++;
						if (count > s && added <= e) {
							added++;
							$tb.append(rows[index]);
						}
					}
					index++;
				}
				ts.processTbody(table, $tb, false);
			}
			updatePageDisplay(table, p);
			if ( !p.isDisabled ) { fixHeight(table, p); }
			if (table.isUpdating) {
				$t.trigger('updateComplete', [ table, true ]);
			}
		},

		showAllRows = function(table, p){
			if ( p.ajax ) {
				pagerArrows(p, true);
			} else {
				p.isDisabled = true;
				$.data(table, 'pagerLastPage', p.page);
				$.data(table, 'pagerLastSize', p.size);
				p.page = 0;
				p.size = p.totalRows;
				p.totalPages = 1;
				$(table)
					.addClass('pagerDisabled')
					.removeAttr('aria-describedby')
					.find('tr.pagerSavedHeightSpacer').remove();
				renderTable(table, table.config.rowsCopy, p);
				$(table).trigger('applyWidgets');
				if (table.config.debug) {
					ts.log('pager disabled');
				}
			}
			// disable size selector
			p.$size.add(p.$goto).add(p.$container.find('.ts-startRow, .ts-page')).each(function(){
				$(this).attr('aria-disabled', 'true').addClass(p.cssDisabled)[0].disabled = true;
			});
		},

		// updateCache if delayInit: true
		updateCache = function(table) {
			var c = table.config,
				p = c.pager;
			c.$table.trigger('updateCache', [ function(){
				var i,
					rows = [],
					n = table.config.cache[0].normalized;
				p.totalRows = n.length;
				for (i = 0; i < p.totalRows; i++) {
					rows.push(n[i][c.columns].$row);
				}
				c.rowsCopy = rows;
				moveToPage(table, p, true);
			} ]);
		},

		moveToPage = function(table, p, pageMoved) {
			if ( p.isDisabled ) { return; }
			var c = table.config,
				$t = $(table),
				l = p.last,
				pg = Math.min( p.totalPages, p.filteredPages );
			if ( pageMoved !== false && p.initialized && $.isEmptyObject(table.config.cache)) {
				return updateCache(table);
			}
			if ( p.page < 0 ) { p.page = 0; }
			if ( p.page > ( pg - 1 ) && pg !== 0 ) { p.page = pg - 1; }
			// fixes issue where one currentFilter is [] and the other is ['','',''],
			// making the next if comparison think the filters are different (joined by commas). Fixes #202.
			l.currentFilters = (l.currentFilters || []).join('') === '' ? [] : l.currentFilters;
			p.currentFilters = (p.currentFilters || []).join('') === '' ? [] : p.currentFilters;
			// don't allow rendering multiple times on the same page/size/totalRows/filters/sorts
			if ( l.page === p.page && l.size === p.size && l.totalRows === p.totalRows &&
				(l.currentFilters || []).join(',') === (p.currentFilters || []).join(',') &&
				l.sortList === (c.sortList || []).join(',') ) { return; }
			if (c.debug) {
				ts.log('Pager changing to page ' + p.page);
			}
			p.last = {
				page : p.page,
				size : p.size,
				// fixes #408; modify sortList otherwise it auto-updates
				sortList : (c.sortList || []).join(','),
				totalRows : p.totalRows,
				currentFilters : p.currentFilters || []
			};
			if (p.ajax) {
				getAjax(table, p);
			} else if (!p.ajax) {
				renderTable(table, c.rowsCopy, p);
			}
			$.data(table, 'pagerLastPage', p.page);
			if (p.initialized && pageMoved !== false) {
				$t
					.trigger('pageMoved', p)
					.trigger('applyWidgets');
				if (table.isUpdating) {
					$t.trigger('updateComplete', [ table, true ]);
				}
			}
		},

		setPageSize = function(table, size, p) {
			p.size = size || p.size || 10;
			p.$size.val(p.size);
			$.data(table, 'pagerLastPage', p.page);
			$.data(table, 'pagerLastSize', p.size);
			p.totalPages = Math.ceil( p.totalRows / p.size );
			p.filteredPages = Math.ceil( p.filteredRows / p.size );
			moveToPage(table, p);
		},

		moveToFirstPage = function(table, p) {
			p.page = 0;
			moveToPage(table, p);
		},

		moveToLastPage = function(table, p) {
			p.page = ( Math.min( p.totalPages, p.filteredPages ) - 1 );
			moveToPage(table, p);
		},

		moveToNextPage = function(table, p) {
			p.page++;
			if ( p.page >= ( Math.min( p.totalPages, p.filteredPages ) - 1 ) ) {
				p.page = ( Math.min( p.totalPages, p.filteredPages ) - 1 );
			}
			moveToPage(table, p);
		},

		moveToPrevPage = function(table, p) {
			p.page--;
			if ( p.page <= 0 ) {
				p.page = 0;
			}
			moveToPage(table, p);
		},

		destroyPager = function(table, p){
			showAllRows(table, p);
			p.$container.hide(); // hide pager
			table.config.appender = null; // remove pager appender function
			p.initialized = false;
			delete table.config.rowsCopy;
			$(table).unbind('destroy.pager sortEnd.pager filterEnd.pager enable.pager disable.pager');
			if (ts.storage) {
				ts.storage(table, p.storageKey, '');
			}
		},

		enablePager = function(table, p, triggered){
			var info,
				c = table.config;
			p.$size.add(p.$goto).add(p.$container.find('.ts-startRow, .ts-page'))
				.removeClass(p.cssDisabled)
				.removeAttr('disabled')
				.attr('aria-disabled', 'false');
			p.isDisabled = false;
			p.page = $.data(table, 'pagerLastPage') || p.page || 0;
			p.size = $.data(table, 'pagerLastSize') || parseInt(p.$size.find('option[selected]').val(), 10) || p.size || 10;
			p.$size.val(p.size); // set page size
			p.totalPages = Math.ceil( Math.min( p.totalRows, p.filteredRows ) / p.size );
			// if table id exists, include page display with aria info
			if ( table.id ) {
				info = table.id + '_pager_info';
				p.$container.find(p.cssPageDisplay).attr('id', info);
				c.$table.attr('aria-describedby', info);
			}
			if ( triggered ) {
				c.$table.trigger('updateRows');
				setPageSize(table, p.size, p);
				hideRowsSetup(table, p);
				fixHeight(table, p);
				if (c.debug) {
					ts.log('pager enabled');
				}
			}
		};

		$this.appender = function(table, rows) {
			var c = table.config,
				p = c.pager;
			if ( !p.ajax ) {
				c.rowsCopy = rows;
				p.totalRows = p.countChildRows ? c.$tbodies.eq(0).children('tr').length : rows.length;
				p.size = $.data(table, 'pagerLastSize') || p.size || 10;
				p.totalPages = Math.ceil( p.totalRows / p.size );
				renderTable(table, rows, p);
				// update display here in case all rows are removed
				updatePageDisplay(table, p, false);
			}
		};

		$this.construct = function(settings) {
			return this.each(function() {
				// check if tablesorter has initialized
				if (!(this.config && this.hasInitialized)) { return; }
				var t, ctrls, fxn,
					table = this,
					c = table.config,
					wo = c.widgetOptions,
					p = c.pager = $.extend( true, {}, $.tablesorterPager.defaults, settings ),
					$t = c.$table,
					// added in case the pager is reinitialized after being destroyed.
					pager = p.$container = $(p.container).addClass('tablesorter-pager').show();
				if (c.debug) {
					ts.log('Pager initializing');
				}
				p.oldAjaxSuccess = p.oldAjaxSuccess || p.ajaxObject.success;
				c.appender = $this.appender;
				if (ts.filter && $.inArray('filter', c.widgets) >= 0) {
					// get any default filter settings (data-value attribute) fixes #388
					p.currentFilters = c.$table.data('lastSearch') || ts.filter.setDefaults(table, c, c.widgetOptions) || [];
					// set, but don't apply current filters
					ts.setFilters(table, p.currentFilters, false);
				}
				if (p.savePages && ts.storage) {
					t = ts.storage(table, p.storageKey) || {}; // fixes #387
					p.page = isNaN(t.page) ? p.page : t.page;
					p.size = ( isNaN(t.size) ? p.size : t.size ) || 10;
					$.data(table, 'pagerLastSize', p.size);
				}

				// skipped rows
				p.regexRows = new RegExp('(' + (wo.filter_filteredRow || 'filtered') + '|' + c.selectorRemove.replace(/^(\w+\.)/g,'') + '|' + c.cssChildRow + ')');

				$t
					.unbind('filterStart filterEnd sortEnd disable enable destroy updateComplete pageSize '.split(' ').join('.pager '))
					.bind('filterStart.pager', function(e, filters) {
						p.currentFilters = filters;
						// don't change page is filters are the same (pager updating, etc)
						if (p.pageReset !== false && (c.lastCombinedFilter || '') !== (filters || []).join('')) {
							p.page = p.pageReset; // fixes #456 & #565
						}
					})
					// update pager after filter widget completes
					.bind('filterEnd.pager sortEnd.pager', function() {
						if (p.initialized) {
							if (c.delayInit && c.rowsCopy && c.rowsCopy.length === 0) {
								// make sure we have a copy of all table rows once the cache has been built
								updateCache(table);
							}
							// update page display first, so we update p.filteredPages
							updatePageDisplay(table, p, false);
							moveToPage(table, p, false);
							c.$table.trigger('applyWidgets');
							fixHeight(table, p);
						}
					})
					.bind('disable.pager', function(e){
						e.stopPropagation();
						showAllRows(table, p);
					})
					.bind('enable.pager', function(e){
						e.stopPropagation();
						enablePager(table, p, true);
					})
					.bind('destroy.pager', function(e){
						e.stopPropagation();
						destroyPager(table, p);
					})
					.bind('updateComplete.pager', function(e, table, triggered){
						e.stopPropagation();
						// table can be unintentionally undefined in tablesorter v2.17.7 and earlier
						if ( !table || triggered ) { return; }
						fixHeight(table, p);
						var $rows = c.$tbodies.eq(0).children('tr').not(c.selectorRemove);
						p.totalRows = $rows.length - ( p.countChildRows ? 0 : $rows.filter('.' + c.cssChildRow).length );
						p.totalPages = Math.ceil( p.totalRows / p.size );
						if ($rows.length && c.rowsCopy && c.rowsCopy.length === 0) {
							// make a copy of all table rows once the cache has been built
							updateCache(table);
						}
						updatePageDisplay(table, p);
						hideRows(table, p);
					})
					.bind('pageSize.pager', function(e,v){
						e.stopPropagation();
						setPageSize(table, parseInt(v, 10) || 10, p);
						hideRows(table, p);
						updatePageDisplay(table, p, false);
						if (p.$size.length) { p.$size.val(p.size); } // twice?
					})
					.bind('pageSet.pager', function(e,v){
						e.stopPropagation();
						p.page = (parseInt(v, 10) || 1) - 1;
						if (p.$goto.length) { p.$goto.val(p.size); } // twice?
						moveToPage(table, p, true);
						updatePageDisplay(table, p, false);
					});

				// clicked controls
				ctrls = [ p.cssFirst, p.cssPrev, p.cssNext, p.cssLast ];
				fxn = [ moveToFirstPage, moveToPrevPage, moveToNextPage, moveToLastPage ];
				pager.find(ctrls.join(','))
					.attr("tabindex", 0)
					.unbind('click.pager')
					.bind('click.pager', function(e){
						e.stopPropagation();
						var i, $t = $(this), l = ctrls.length;
						if ( !$t.hasClass(p.cssDisabled) ) {
							for (i = 0; i < l; i++) {
								if ($t.is(ctrls[i])) {
									fxn[i](table, p);
									break;
								}
							}
						}
					});

				// goto selector
				p.$goto = pager.find(p.cssGoto);
				if ( p.$goto.length ) {
					p.$goto
						.unbind('change')
						.bind('change', function(){
							p.page = $(this).val() - 1;
							moveToPage(table, p, true);
							updatePageDisplay(table, p, false);
						});
				}

				// page size selector
				p.$size = pager.find(p.cssPageSize);
				if ( p.$size.length ) {
					// setting an option as selected appears to cause issues with initial page size
					p.$size.find('option').removeAttr('selected');
					p.$size.unbind('change.pager').bind('change.pager', function() {
						p.$size.val( $(this).val() ); // in case there are more than one pagers
						if ( !$(this).hasClass(p.cssDisabled) ) {
							setPageSize(table, parseInt( $(this).val(), 10 ), p);
							changeHeight(table, p);
						}
						return false;
					});
				}

				// clear initialized flag
				p.initialized = false;
				// before initialization event
				$t.trigger('pagerBeforeInitialized', p);

				enablePager(table, p, false);

				if ( typeof(p.ajaxUrl) === 'string' ) {
					// ajax pager; interact with database
					p.ajax = true;
					//When filtering with ajax, allow only custom filtering function, disable default filtering since it will be done server side.
					c.widgetOptions.filter_serversideFiltering = true;
					c.serverSideSorting = true;
					moveToPage(table, p);
				} else {
					p.ajax = false;
					// Regular pager; all rows stored in memory
					$(this).trigger("appendCache", true);
					hideRowsSetup(table, p);
				}

				changeHeight(table, p);

				// pager initialized
				if (!p.ajax) {
					p.initialized = true;
					$(table).trigger('pagerInitialized', p);
				}
			});
		};

	}() });

	// see #486
	ts.showError = function(table, message){
		$(table).each(function(){
			var $row,
				c = this.config,
				errorRow = c.pager && c.pager.cssErrorRow || c.widgetOptions.pager_css && c.widgetOptions.pager_css.errorRow || 'tablesorter-errorRow';
			if (c) {
				if (typeof message === 'undefined') {
					c.$table.find('thead').find(c.selectorRemove).remove();
				} else {
					$row = ( /tr\>/.test(message) ? $(message) : $('<tr><td colspan="' + c.columns + '">' + message + '</td></tr>') )
						.click(function(){
							$(this).remove();
						})
						// add error row to thead instead of tbody, or clicking on the header will result in a parser error
						.appendTo( c.$table.find('thead:first') )
						.addClass( errorRow + ' ' + c.selectorRemove.replace(/^(\w+\.)/g,'') )
						.attr({
							role : 'alert',
							'aria-live' : 'assertive'
						});
				}
			}
		});
	};

// extend plugin scope
$.fn.extend({
	tablesorterPager: $.tablesorterPager.construct
});

})(jQuery);
