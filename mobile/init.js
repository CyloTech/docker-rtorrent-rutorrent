/*** Configurable Options ***/
plugin.enableAutodetect = true;
plugin.tabletsDetect = true;
plugin.eraseWithDataDefault = false;
plugin.sort = '-addtime'; /* 'name', 'size', 'uploaded', 'downloaded', 'done', 'eta', 'ul', 'dl', 'ratio', 'addtime', 'seedingtime'. Add preceding negative for descending sort. */
/*** End Configurable Options ***/

plugin.statusFilter = {downloading: 1, completed: 2, label: 4, all: 3, tracker: 5, active: 6, inactive: 7, error: 8};
plugin.navFilter = undefined;
plugin.torrents = null;
plugin.torrentsPrev = null;
plugin.torrent = undefined;
plugin.lastHref = "";
plugin.scrollTop = 0;
plugin.currFilter = plugin.statusFilter.all;
plugin.labelInEdit = false;
plugin.eraseWithDataLoaded = false;
plugin.ratioGroupsLoaded = false;
plugin.throttleLoaded = false;
plugin.seedingtimeLoaded = false;
plugin.getDirLoaded = false;
plugin.bootstrapJS = false;

plugin.THEME_STORAGE_KEY = 'mobile-ui-theme';
plugin.CHROME_STORAGE_KEY = 'mobile-ui-chrome-expanded';
plugin.searchTerm = '';
plugin.lastUpdatedAt = null;
plugin.chromeExpanded = false;
plugin.getDirTargetInput = 'dir_edit';
plugin.createTask = null;

plugin.syncLayoutMetrics = function() {
  var top = $('#torrentsTopBar').outerHeight(true) || 0;
  var bottom = $('#mainNavbar').outerHeight(true) || 0;
  document.documentElement.style.setProperty('--mobile-top-offset', top + 'px');
  document.documentElement.style.setProperty('--mobile-bottom-offset', bottom + 'px');
};

plugin.applyTheme = function(mode) {
  var m = mode === 'dark' ? 'dark' : 'light';
  document.documentElement.setAttribute('data-theme', m);
  try {
    localStorage.setItem(plugin.THEME_STORAGE_KEY, m);
  } catch (e) {}
  plugin.updateThemeToggleUi();
};

plugin.updateThemeToggleUi = function() {
  var dark = document.documentElement.getAttribute('data-theme') === 'dark';
  var $btn = $('#navTheme');
  if ($btn.length) {
    $btn.attr('aria-pressed', dark ? 'true' : 'false');
    $('#navThemeIconMoon').toggleClass('hidden', dark);
    $('#navThemeIconSun').toggleClass('hidden', !dark);
    $btn.attr('title', dark ? 'Light mode' : 'Dark mode');
  }
};

plugin.applyChromeState = function(expanded) {
  plugin.chromeExpanded = !!expanded;
  $('#torrentsTopBar').toggleClass('hero-expanded', plugin.chromeExpanded);
  $('#torrentsTopBar').toggleClass('hero-collapsed', !plugin.chromeExpanded);
  $('#toggleChrome').attr('aria-expanded', plugin.chromeExpanded ? 'true' : 'false');
  $('#toggleChrome').attr('title', plugin.chromeExpanded ? 'Hide filters and search' : 'Show filters and search');
  $('#toggleChromeText').text(plugin.chromeExpanded ? 'Collapse' : 'Expand');
  setTimeout(function() {
    plugin.syncLayoutMetrics();
  }, 10);
};

plugin.initChromeState = function() {
  var stored = null;
  try {
    stored = localStorage.getItem(plugin.CHROME_STORAGE_KEY);
  } catch (e) {}
  plugin.applyChromeState(stored === '1');
};

plugin.toggleChrome = function() {
  plugin.applyChromeState(!plugin.chromeExpanded);
  try {
    localStorage.setItem(plugin.CHROME_STORAGE_KEY, plugin.chromeExpanded ? '1' : '0');
  } catch (e) {}
};

plugin.initTheme = function() {
  var stored = null;
  try {
    stored = localStorage.getItem(plugin.THEME_STORAGE_KEY);
  } catch (e) {}
  var initial = stored;
  if (initial !== 'dark' && initial !== 'light') {
    initial =
      window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
        ? 'dark'
        : 'light';
  }
  plugin.applyTheme(initial);
};

plugin.toggleTheme = function() {
  var next = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
  plugin.applyTheme(next);
};

plugin.escapeHtml = function(value) {
  return $('<div>').text(value == null ? '' : String(value)).html();
};

plugin.escapeAttr = function(value) {
  return plugin.escapeHtml(value).replace(/"/g, '&quot;');
};

plugin.escapeJsString = function(value) {
  return String(value == null ? '' : value)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'");
};

plugin.setListState = function(title, copy) {
  $('#listStateTitle').text(title || '');
  $('#listStateCopy').text(copy || '');
  $('#listState').css('display', '');
  $('#list table').css('display', 'none');
};

plugin.clearListState = function() {
  $('#listState').css('display', 'none');
  $('#list table').css('display', '');
};

plugin.renderDetailsPlaceholder = function(target, title, copy) {
  $(target).html(
    '<div class="details-empty">' +
      '<div class="empty-state-icon">' +
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="size-5" aria-hidden="true">' +
          '<path stroke-linecap="round" stroke-linejoin="round" d="M8 19h8a2 2 0 0 0 2-2V7.414a2 2 0 0 0-.586-1.414l-2.414-2.414A2 2 0 0 0 13.586 3H8a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2Z" />' +
          '<path stroke-linecap="round" stroke-linejoin="round" d="M14 3v4h4" />' +
        '</svg>' +
      '</div>' +
      '<h3 class="empty-state-title">' + plugin.escapeHtml(title) + '</h3>' +
      '<p class="empty-state-copy">' + plugin.escapeHtml(copy) + '</p>' +
    '</div>'
  );
};

plugin.updateLastUpdatedLabel = function() {
  if (!plugin.lastUpdatedAt) {
    $('#lastUpdatedLabel').text('Waiting for first refresh');
    return;
  }
  $('#lastUpdatedLabel').text('Updated ' + plugin.lastUpdatedAt.toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit'
  }));
};

plugin.updateSpeedVisibility = function() {
  var up = $.trim($('#upspeed').text());
  var down = $.trim($('#downspeed').text());
  $('#navSpeed').css('display', (up || down) ? '' : 'none');
};

plugin.dropdownPortal = {
  openKey: null
};

plugin.closeDropdownPortal = function() {
  $('#mobileDropdownPortal .mobile-dropdown-menu').css('display', 'none');
  $('.dropdown').removeClass('open');
  plugin.dropdownPortal.openKey = null;
};

plugin.positionDropdownPortal = function(key, anchorEl) {
  var $root = $('.dropdown[data-dropdown-key="' + key + '"]');
  var $menu = $('#mobileDropdownPortal .mobile-dropdown-menu[data-dropdown-key="' + key + '"]');
  var $anchor = anchorEl ? $(anchorEl) : $root.children('a').first();
  if (!$menu.length || !$anchor.length) {
    return;
  }

  $menu.css({ display: 'block', visibility: 'hidden', width: '' });
  var desiredWidth = Math.max($anchor.outerWidth(), $menu.outerWidth());
  var maxWidth = $(window).width() - 24;
  desiredWidth = Math.min(desiredWidth, maxWidth);
  var offs = $anchor.offset();
  var left = Math.min(Math.max(offs.left, 12), $(window).width() - desiredWidth - 12);
  var top = offs.top + $anchor.outerHeight() + 8;

  $menu.css({
    left: left,
    top: top,
    width: desiredWidth,
    visibility: 'visible',
    display: 'block'
  });
  $('.dropdown').removeClass('open');
  $root.addClass('open');
  plugin.dropdownPortal.openKey = key;
};

plugin.toggleDropdownPortal = function(key, anchorEl) {
  if (plugin.dropdownPortal.openKey === key) {
    plugin.closeDropdownPortal();
    return;
  }
  plugin.positionDropdownPortal(key, anchorEl);
};

plugin.initDropdownPortals = function() {
  var portal = $('#mobileDropdownPortal');
  if (!portal.length) {
    return;
  }

  var configs = [
    { key: 'status', root: '#torrentsStatus' },
    { key: 'labels', root: '#torrentsLabels' },
    { key: 'trackers', root: '#torrentsTrackers' }
  ];

  $.each(configs, function(_, config) {
    var $root = $(config.root);
    var $anchor = $root.children('a').first();
    var $menu = $root.children('ul').first();
    if (!$root.length || !$anchor.length || !$menu.length) {
      return;
    }

    $root.attr('data-dropdown-key', config.key);
    $menu.attr('data-dropdown-key', config.key).addClass('mobile-dropdown-menu').appendTo(portal);
    $anchor.off('click').on('click.mobileDropdown', function(ev) {
      ev.preventDefault();
      ev.stopImmediatePropagation();
      plugin.toggleDropdownPortal(config.key, this);
      return false;
    });
    $menu.off('click').on('click.mobileDropdown', 'a', function() {
      setTimeout(function() {
        plugin.closeDropdownPortal();
      }, 0);
    });
  });

  $(document)
    .off('click.mobileDropdown')
    .on('click.mobileDropdown', function(ev) {
      if (!$(ev.target).closest('.mobile-dropdown-menu, .dropdown > a').length) {
        plugin.closeDropdownPortal();
      }
    });

  $(window)
    .off('resize.mobileDropdown scroll.mobileDropdown')
    .on('resize.mobileDropdown scroll.mobileDropdown', function() {
      plugin.closeDropdownPortal();
    });
};

plugin.getDropdownMenu = function(key, fallbackRoot) {
  var $menu = $('#mobileDropdownPortal .mobile-dropdown-menu[data-dropdown-key="' + key + '"]');
  if ($menu.length) {
    return $menu;
  }

  return $(fallbackRoot + ' > ul').first();
};

plugin.setCreateTaskState = function(kind, title, copy, showDownload) {
  $('#createTaskState').removeClass('page-callout-success page-callout-danger page-callout-muted');
  $('#createTaskState').addClass(kind || 'page-callout-muted').css('display', '');
  $('#createTaskTitle').text(title || '');
  $('#createTaskCopy').text(copy || '');
  $('#createTaskActions').css('display', showDownload ? '' : 'none');
};

plugin.updateSummaryCards = function(summary) {
  $('#summaryAllCount').text(summary.total);
  $('#summaryDownloadingCount').text(summary.downloading);
  $('#summaryCompletedCount').text(summary.completed);
  $('#summaryActiveCount').text(summary.active);
};

plugin.syncSummaryCardState = function() {
  $('#summaryGrid .summary-card').removeClass('is-active');
  if (plugin.currFilter === plugin.statusFilter.downloading) {
    $('#summaryDownloadingCard').addClass('is-active');
  } else if (plugin.currFilter === plugin.statusFilter.completed) {
    $('#summaryCompletedCard').addClass('is-active');
  } else if (plugin.currFilter === plugin.statusFilter.active) {
    $('#summaryActiveCard').addClass('is-active');
  } else {
    $('#summaryAllCard').addClass('is-active');
  }
};

plugin.applySearchFilter = function() {
  var rawTerm = $('#torrentSearch').val() || plugin.searchTerm || '';
  plugin.searchTerm = $.trim(rawTerm).toLowerCase();

  var matchingRows = 0;
  $('.torrentBlock').each(function() {
    var $row = $(this);
    var baseVisible = $row.data('baseVisible') !== false;
    var haystack = String($row.attr('data-search-text') || '').toLowerCase();
    var matches = plugin.searchTerm.length === 0 || haystack.indexOf(plugin.searchTerm) >= 0;
    var shouldShow = baseVisible && matches;
    if (shouldShow) {
      matchingRows++;
    }
    $row.css('display', shouldShow ? '' : 'none');
  });

  var totalRows = $('.torrentBlock').length;
  var visibleRows = matchingRows;
  var copy;
  if ($('#torrentsList').is(':visible')) {
    if (totalRows === 0) {
      plugin.setListState('No torrents yet', 'Use Add to upload a torrent file or paste a magnet / URL.');
    } else if (visibleRows === 0) {
      copy = plugin.searchTerm
        ? 'Try a different search phrase or switch to another status filter.'
        : 'Switch filters or refresh to pull in new transfers.';
      plugin.setListState('Nothing matches this view', copy);
    } else {
      plugin.clearListState();
    }
  }

  $('#visibleTorrentCount').text(
    visibleRows + ' torrent' + (visibleRows === 1 ? '' : 's') + ' visible'
  );
  plugin.syncSummaryCardState();
};

plugin.clearSearch = function() {
  $('#torrentSearch').val('');
  plugin.searchTerm = '';
  $('#clearSearch').css('display', 'none');
  plugin.applySearchFilter();
};

plugin.renderTorrentRow = function(v, statusText, percent, trackerNames) {
  var trackerCount = trackerNames.length;
  var statusVariant = (v.state & dStatus.error)
    ? 'error'
    : (v.done == 1000 ? 'completed' : ((v.ul || v.dl) ? 'active' : 'downloading'));
  var secondaryLabel = (v.done == 1000) ? theUILang.Ratio : theUILang.ETA;
  var secondaryValue = (v.done == 1000)
    ? ((v.ratio == -1) ? '\u221e' : theConverter.round(v.ratio / 1000, 3))
    : ((v.eta == -1) ? '\u221e' : theConverter.time(v.eta));
  var trackerText = trackerCount > 0
    ? trackerCount + ' tracker' + (trackerCount === 1 ? '' : 's')
    : 'No trackers';
  var searchText = [v.name, v.label, statusText, v.msg, trackerText, trackerNames.join(' ')].join(' ');
  var metaBadge = v.label
    ? '<span class="meta-pill">' + plugin.escapeHtml(v.label) + '</span>'
    : '<span class="meta-pill">' + plugin.escapeHtml(theUILang.No_label) + '</span>';
  var issueText = v.msg
    ? '<span class="text-danger">' + plugin.escapeHtml(v.msg) + '</span>'
    : plugin.escapeHtml(trackerText);

  return '' +
    '<tr id="' + v.hash + '" data-search-text="' + plugin.escapeAttr(searchText) + '" class="torrentBlock status' + (v.done == 1000 ? 'Completed' : 'Downloading') + ' state' + ((v.ul || v.dl) ? 'Active' : 'Inactive') + ' error' + ((v.state & dStatus.error) ? 'Yes' : 'No') + ' label' + plugin.labelIds[v.label] + '">' +
      '<td onclick="mobile.showDetails(\'' + plugin.escapeAttr(v.hash) + '\');">' +
        '<div class="torrent-row">' +
          '<div class="torrent-row-top">' +
            '<div class="torrent-row-head">' +
              '<h5>' + plugin.escapeHtml(v.name) + '</h5>' +
              '<div class="torrent-row-badges">' +
                '<span class="status-pill ' + statusVariant + '">' + plugin.escapeHtml(statusText) + '</span>' +
                metaBadge +
              '</div>' +
            '</div>' +
            '<div class="torrent-row-percent">' + plugin.escapeHtml(percent + '%') + '</div>' +
          '</div>' +
          '<div class="torrent-row-metrics">' +
            '<div class="metric-card"><span class="metric-label">' + plugin.escapeHtml(secondaryLabel) + '</span><strong class="metric-value">' + plugin.escapeHtml(secondaryValue) + '</strong></div>' +
            '<div class="metric-card"><span class="metric-label">' + plugin.escapeHtml(theUILang.Size) + '</span><strong class="metric-value">' + plugin.escapeHtml(theConverter.bytes(v.size, 2)) + '</strong></div>' +
            '<div class="metric-card"><span class="metric-label">' + plugin.escapeHtml(theUILang.Down_speed) + '</span><strong class="metric-value">' + plugin.escapeHtml(v.dl ? theConverter.speed(v.dl) : '0 B/s') + '</strong></div>' +
            '<div class="metric-card"><span class="metric-label">' + plugin.escapeHtml(theUILang.Ul_speed) + '</span><strong class="metric-value">' + plugin.escapeHtml(v.ul ? theConverter.speed(v.ul) : '0 B/s') + '</strong></div>' +
          '</div>' +
          '<div class="torrent-row-foot">' + issueText + '</div>' +
          '<div class="progress' + ((v.done == 1000) ? '' : ' active') + '">' +
            '<div class="progress-bar progress-bar-striped" style="width: ' + percent + '%;">' + plugin.escapeHtml(percent + '%') + '</div>' +
          '</div>' +
        '</div>' +
      '</td>' +
    '</tr>';
};

/**
 * jQuery.browser was removed upstream; mobile detection must exist before plugin.disableOthers().
 * (http://detectmobilebrowser.com/)
 */
(function (a) {
  (jQuery.browser = jQuery.browser || {}).mobile =
    /(android|bb\d+|meego).+mobile|avantgo|bada\/|blackberry|blazer|compal|elaine|fennec|hiptop|iemobile|ip(hone|od)|iris|kindle|lge |maemo|midp|mmp|mobile.+firefox|netfront|opera m(ob|in)i|palm( os)?|phone|p(ixi|re)\/|plucker|pocket|psp|series(4|6)0|symbian|treo|up\.(browser|link)|vodafone|wap|windows (ce|phone)|xda|xiino/i.test(a) ||
    /1207|6310|6590|3gso|4thp|50[1-6]i|770s|802s|a wa|abac|ac(er|oo|s\-)|ai(ko|rn)|al(av|ca|co)|amoi|an(ex|ny|yw)|aptu|ar(ch|go)|as(te|us)|attw|au(di|\-m|r |s )|avan|be(ck|ll|nq)|bi(lb|rd)|bl(ac|az)|br(e|v)w|bumb|bw\-(n|u)|c55\/|capi|ccwa|cdm\-|cell|chtm|cldc|cmd\-|co(mp|nd)|craw|da(it|ll|ng)|dbte|dc\-s|devi|dica|dmob|do(c|p)o|ds(12|\-d)|el(49|ai)|em(l2|ul)|er(ic|k0)|esl8|ez([4-7]0|os|wa|ze)|fetc|fly(\-|_)|g1 u|g560|gene|gf\-5|g\-mo|go(\.w|od)|gr(ad|un)|haie|hcit|hd\-(m|p|t)|hei\-|hi(pt|ta)|hp( i|ip)|hs\-c|ht(c(\-| |_|a|g|p|s|t)|tp)|hu(aw|tc)|i\-(20|go|ma)|i230|iac( |\-|\/)|ibro|idea|ig01|ikom|im1k|inno|ipaq|iris|ja(t|v)a|jbro|jemu|jigs|kddi|keji|kgt( |\/)|klon|kpt |kwc\-|kyo(c|k)|le(no|xi)|lg( g|\/(k|l|u)|50|54|\-[a-w])|libw|lynx|m1\-w|m3ga|m50\/|ma(te|ui|xo)|mc(01|21|ca)|m\-cr|me(rc|ri)|mi(o8|oa|ts)|mmef|mo(01|02|bi|de|do|t(\-| |o|v)|zz)|mt(50|p1|v )|mwbp|mywa|n10[0-2]|n20[2-3]|n30(0|2)|n50(0|2|5)|n7(0(0|1)|10)|ne((c|m)\-|on|tf|wf|wg|wt)|nok(6|i)|nzph|o2im|op(ti|wv)|oran|owg1|p800|pan(a|d|t)|pdxg|pg(13|\-([1-8]|c))|phil|pire|pl(ay|uc)|pn\-2|po(ck|rt|se)|prox|psio|pt\-g|qa\-a|qc(07|12|21|32|60|\-[2-7]|i\-)|qtek|r380|r600|raks|rim9|ro(ve|zo)|s55\/|sa(ge|ma|mm|ms|ny|va)|sc(01|h\-|oo|p\-)|sdk\/|se(c(\-|0|1)|47|mc|nd|ri)|sgh\-|shar|sie(\-|m)|sk\-0|sl(45|id)|sm(al|ar|b3|it|t5)|so(ft|ny)|sp(01|h\-|v\-|v )|sy(01|mb)|t2(18|50)|t6(00|10|18)|ta(gt|lk)|tcl\-|tdg\-|tel(i|m)|tim\-|t\-mo|to(pl|sh)|ts(70|m\-|m3|m5)|tx\-9|up(\.b|g1|si)|utst|v400|v750|veri|vi(rg|te)|vk(40|5[0-3]|\-v)|vm40|voda|vulc|vx(52|53|60|61|70|80|81|83|85|98)|w3c(\-| )|webc|whit|wi(g |nc|nw)|wmlb|wonu|x700|yas\-|your|zeto|zte\-/i.test(
      a.substr(0, 4)
    );
})(navigator.userAgent || navigator.vendor || window.opera);
if (plugin.tabletsDetect && !jQuery.browser.mobile) {
  (function (a) {
    (jQuery.browser = jQuery.browser || {}).mobile = /android|ipad|playbook|silk/i.test(a);
  })(navigator.userAgent || navigator.vendor || window.opera);
}

var pageToHash = {
  'torrentsList': '',
  'torrentDetails': 'details',
  'globalSettings': 'settings',
  'torrentSort': 'sort',
  'addTorrent': 'add',
  'createTorrent': 'create',
  'confimTorrentDelete': 'delete',
  'getDirList': 'filesystem'
};

var detailsIdToLangId = {
  'status' : 'Status',
  'done' : 'Done',
  'downloaded' : 'Downloaded',
  'size' : 'Size',
  'timeElapsed' : 'Time_el',
  'remaining' : 'Remaining',
  'eta' : 'ETA',
  'ratio' : 'Ratio',
  'downloadSpeed' : 'Down_speed',
  'wasted' : 'Wasted',
  'uploaded' : 'Uploaded',
  'uploadSpeed' : 'Ul_speed',
  'seeds' : 'Seeds',
  'peers' : 'Peers',
  'label' : 'Label',
  'priority' : 'Priority',
  'trackerStatus' : 'Track_status',
  'created' : 'Created_on',
  'savePath' : 'Save_path',
  'comment' : 'Comment'
};

var peersIdToLangId = {
  'address' : 'Address',
  'client' : 'ClientVersion',
  'flags' : 'Flags',
  'done' : 'Done',
  'downloaded' : 'Downloaded',
  'uploaded' : 'Uploaded',
  'dl' : 'DL',
  'ul' : 'UL',
  'peer_dl' : 'PeerDL',
  'peer_downloaded' : 'PeerDownloaded',
};

if(!$type(theWebUI.getTrackerName))
{
  theWebUI.getTrackerName = function(announce)
  {
    var domain = '';
    if(announce)
    {
      var parts = announce.match(/^(?:([^:\/?#]+):)?(?:\/\/((?:(([^:@]*):?([^:@]*))?@)?([^:\/?#]*)(?::(\d*))?))?((((?:[^?#\/]*\/)*)([^?#]*))(?:\?([^#]*))?(?:#(.*))?)/);
      if(parts && (parts.length>6))
      {
        domain = parts[6];
        if(!domain.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/))
        {
          parts = domain.split(".");
          if(parts.length>2)
          {
            if($.inArray(parts[parts.length-2]+"", ["co", "com", "net", "org"])>=0 ||
            $.inArray(parts[parts.length-1]+"", ["uk"])>=0)
            parts = parts.slice(parts.length-3);
            else
            parts = parts.slice(parts.length-2);
            domain = parts.join(".");
          }
        }
      }
    }
    return(domain);
  }
}

$(document).on('blur', 'input, select, textarea', function() {
  setTimeout(function() {
    $(window).scrollTop($(window).scrollTop()+1);
  }, 0);
});

var isEqual = function (a, b) {
  // Create arrays of property names
  var aProps = Object.getOwnPropertyNames(a);
  var bProps = Object.getOwnPropertyNames(b);

  // If number of properties is different,
  // objects are not equivalent
  if (aProps.length != bProps.length) {
      return false;
  }

  for (var i = 0; i < aProps.length; i++) {
      var propName = aProps[i];

      // Skip checking if these properties are equal
      if (propName == 'free_diskspace') {
        continue;
      }

      // If values of same property are not equal,
      // objects are not equivalent
      if (a[propName] !== b[propName]) {
          return false;
      }
  }

  // If we made it this far, objects
  // are considered equivalent
  return true;
};

plugin.getRatioData = function(id)
{
  var curNo = -1;
  var s = this.torrents[id].ratiogroup;
  var arr = s.match(/rat_(\d{1,2})/);
  if(arr && (arr.length>1)) {
    curNo = arr[1];
  }
  return(curNo);
};

plugin.toogleDisplay = function(s) {
  if (s.css('display') == 'none') {
    s.css('display', '')
  } else{
    s.css('display', 'none');
  }
};

plugin.backListener = function() {
  if (this.lastHref != window.location.href) {
    if (window.location.hash == '#details') {
      if (this.torrent != undefined) {
        this.showDetails(this.torrent.hash);
      }
    } else if (window.location.hash == '#settings') {
      this.showSettings();
    } else if (window.location.hash == '#add') {
      this.addTorrent();
    } else if (window.location.hash == '#create') {
      this.showCreateTorrent();
    } else if (window.location.hash == '#sort') {
      this.showSort();
    } else if (window.location.hash == '#delete') {
      if (this.torrent != undefined) {
        this.delete();
      }
    } else {
      this.showList();
    }
  }
};

plugin.request = function(url, func) {
  theWebUI.requestWithTimeout(url, function(d){if (func != undefined) func(d);}, function(){}, function(){});
};

plugin.setHash = function(page) {
  window.location.hash = pageToHash[page];
  this.lastHref = window.location.href;
};

plugin.showAlert = function(message,alerttype) {
  $('#alert_placeholder').append('<div id="alertdiv" class="alert alert-dismissible fade in navbar-fixed-top '+ alerttype +'" role="alert"><button type="button" class="close" data-dismiss="alert"><span aria-hidden="true">&times;</span><span class="sr-only">Close</span></button>'+ message +'</div>');
  setTimeout(function() {
    $('#alertdiv').removeClass('in');
    setTimeout(function() {
      $("#alertdiv").remove();
    }, 1500);
  }, 5000);
};

plugin.createiFrame = function() {
  $('#addTorrent').prepend('<iframe id="uploadFrame" name="uploadFrame" style="visibility: hidden; width: 0; height: 0; line-height: 0; font-size: 0; border: 0;"></iframe>')
  $('#uploadFrame').on('load', function() {
    var d = (this.contentDocument || this.contentWindow.document);

    if(d && (d.location.href != "about:blank")) {
      var matchedRegex = d.body.innerHTML.match(/noty\(".*"\+(.*),"(.*)"/);
      if (matchedRegex != null) {
        var message = '';
        try {message = eval(matchedRegex[1]);} catch(e) { }
        if (message != '') {
          if(matchedRegex[2] == "success") {
            plugin.showAlert(message,"alert-success");
          } else if (matchedRegex[2] == "error") {
            plugin.showAlert(message,"alert-danger");
          }
        }
      }
    }
    $('#uploadFrame').remove();
    plugin.update(true);
  });
};

plugin.showPage = function(page) {
  if (window.location.hash == "" && page != 'torrentsList') {
    this.scrollTop = $(window).scrollTop();
  }
  $('.mainContainer').css('display', 'none');
  $('.torrentControl').css('display', 'none');
  $('#' + page).css('display', '');
  if (page == 'torrentsList') {
    window.scrollTo(0,this.scrollTop);
  }
  else {
    window.scrollTo(0,0);
  }
  this.setHash(page);
  if (page == 'torrentsList') {
    this.applySearchFilter();
  }
  this.syncLayoutMetrics();
};

plugin.showList = function() {
  this.showPage('torrentsList');
};

plugin.filter = function(f, self, l) {
  $('.torrentBlock').data('baseVisible', true);
  $('#torrentsList ul li').removeClass('active');
  $('#torrentsStatus > a > span').html(theUILang.Status);
  $('#torrentsLabels > a > span').html(theUILang.Labels);
  $('#torrentsTrackers > a > span').html(theUILang.Trackers);

  if (f == this.statusFilter.label) {
    this.navFilter = l;
    $('.torrentBlock').data('baseVisible', false);
    $('.label' + this.labelIds[l]).data('baseVisible', true);
    $('#torrentsLabels').addClass('active');
    $('#torrentsLabels > a > span').html(l === '' ? theUILang.No_label : l);
  } else if (f == this.statusFilter.tracker) {
    this.navFilter = l;
    $('.torrentBlock').data('baseVisible', false);
    $('.tracker' + this.trackerIds[l]).data('baseVisible', true);
    $('#torrentsTrackers').addClass('active');
    $('#torrentsTrackers > a > span').html(l);
  } else {
    this.navFilter = undefined;
    $('#torrentsStatus').addClass('active');
    if (f == this.statusFilter.downloading) {
      $('.torrentBlock').each(function() {
        $(this).data('baseVisible', $(this).hasClass('statusDownloading'));
      });
      $('#torrentsStatus > a > span').html(theUILang.Downloading);
    } else if (f == this.statusFilter.completed) {
      $('.torrentBlock').each(function() {
        $(this).data('baseVisible', $(this).hasClass('statusCompleted'));
      });
      $('#torrentsStatus > a > span').html(theUILang.Finished);
    } else if (f == this.statusFilter.active) {
      $('.torrentBlock').each(function() {
        $(this).data('baseVisible', $(this).hasClass('stateActive'));
      });
      $('#torrentsStatus > a > span').html(theUILang.Active);
    } else if (f == this.statusFilter.inactive) {
      $('.torrentBlock').each(function() {
        $(this).data('baseVisible', $(this).hasClass('stateInactive'));
      });
      $('#torrentsStatus > a > span').html(theUILang.Inactive);
    } else if (f == this.statusFilter.error) {
      $('.torrentBlock').each(function() {
        $(this).data('baseVisible', $(this).hasClass('errorYes'));
      });
      $('#torrentsStatus > a > span').html(theUILang.Error);
    } else {
      $('#torrentsStatus > a > span').html(theUILang.All);
    }
  }
  this.currFilter = f;
  this.applySearchFilter();
};

plugin.showSettings = function() {
  this.request("?action=gettotal", function(total) {
    $('#dlLimit').html('');
    $('#ulLimit').html('');

    var speeds = theWebUI.settings["webui.speedlistdl"].split(",");

    for (var i = 0; i < speeds.length; i++) {
      var spd = speeds[i] * 1024;
      $('#dlLimit').append('<option' + (spd == total.rateDL ? ' selected' : '') + ' value="' + spd + '">' + theConverter.speed(spd) + '</option>');
    };
    $('#dlLimit').append('<option' + ((total.rateDL <= 0 || total.rateDL >= 327625*1024) ? ' selected' : '') + ' value="' + 327625*1024 + '">' + theUILang.unlimited + '</option>');

    speeds=theWebUI.settings["webui.speedlistul"].split(",");

    for (var i = 0; i < speeds.length; i++) {
      var spd = speeds[i] * 1024;
      $('#ulLimit').append('<option' + (spd == total.rateUL ? ' selected' : '') + ' value="' + spd + '">' + theConverter.speed(spd) + '</option>');
    };
    $('#ulLimit').append('<option' + ((total.rateUL <= 0 || total.rateUL >= 327625*1024) ? ' selected' : '') + ' value="' + 327625*1024 + '">' + theUILang.unlimited + '</option>');

    plugin.showPage('globalSettings');
  });
};

plugin.showSort = function() {
  $('#sortOption option').prop('selected', false);
  $('#sort_asc').prop('checked', false);
  $('#sort_desc').prop('checked', false);
  
  var sort = '';
  if(plugin.sort[0] === "-") {
    sort = plugin.sort.substr(1);
    $('#sort_desc').prop('checked', true);
  } else {
    sort = plugin.sort;
    $('#sort_asc').prop('checked', true);
  }
  
  sortHtml = '<option value="name">' + theUILang.Name + '</option>' +
              '<option value="size">' + theUILang.Size + '</option>' +
              '<option value="uploaded">' + theUILang.Uploaded + '</option>' +
              '<option value="downloaded">' + theUILang.Downloaded + '</option>' +
              '<option value="done">' + theUILang.Done + '</option>' +
              '<option value="eta">' + theUILang.ETA + '</option>' +
              '<option value="ul">' + theUILang.Ul_speed + '</option>' +
              '<option value="dl">' + theUILang.Down_speed + '</option>' +
              '<option value="ratio">' + theUILang.Ratio + '</option>';
  
  if (this.seedingtimeLoaded) {
    sortHtml += '<option value="addtime">' + theUILang.addTime + '</option>' +
                '<option value="seedingtime">' + theUILang.seedingTime + '</option>'
  }
  $('#sortOption').html(sortHtml);
  $('#sortOption option[value=' + sort + ']').prop('selected', true);
  
  plugin.showPage('torrentSort');
};

plugin.refresh = function() {
  plugin.setListState('Refreshing torrents', 'Pulling the newest status information from ruTorrent.');
  plugin.update(true);
};

plugin.setDLLimit = function() {
  theWebUI.setDLRate($('#dlLimit').val());
};

plugin.setULLimit = function() {
  theWebUI.setULRate($('#ulLimit').val());
};

plugin.setSort = function() {
  var sort = $('#sortOption').val();
  if($('#sort_desc').prop('checked')) {
    sort = '-' + sort
  }
  plugin.sort = sort;
  plugin.update(true);
  history.go(-1);
};

plugin.addTorrent = function() {
  this.showPage('addTorrent');
  var used = ($('#dir_edit').outerWidth(true) - $('#dir_edit').width()) + $('#showGetDir').outerWidth(true) + 1;
  $('#dir_edit').width($('#addTorrentFile').outerWidth(true) - used);
};

plugin.showCreateTorrent = function() {
  this.showPage('createTorrent');
  var used = ($('#create_path_edit').outerWidth(true) - $('#create_path_edit').width()) + $('#showCreateGetDir').outerWidth(true) + 1;
  $('#create_path_edit').width($('#createTorrentForm').outerWidth(true) - used);
};

plugin.fillLabel = function(label) {
  if (this.labelInEdit) {
    return;
  }

  $('#torrentDetails #label td:last').text(label + ' ').append('<button class="btn btn-default btn-sm" type="button" onclick="mobile.editLabel();" title="Edit">✎</button>');
};

plugin.fillDetails = function(d) {
  $('#torrentName').text(d.name);

  var percent = d.done / 10.0;
  var statusText = theWebUI.getStatusIcon(d)[1];
  $('#torrentProgress').removeClass('active');
  if (d.done != 1000) {
    $('#torrentProgress').addClass('active');
  }
  $('#torrentProgress .progress-bar').css('width', percent + '%');
  $('#torrentProgress .progress-bar').text(percent + '%');

  $('#torrentHeaderStatus').text(statusText);
  $('#torrentHeaderProgressValue').text(percent + '%');
  $('#torrentHeaderETAValue').html((d.eta == -1) ? "&#8734;" : theConverter.time(d.eta));
  $('#torrentHeaderRatioValue').html((d.ratio == -1) ? "&#8734;" : theConverter.round(d.ratio/1000,3));
  $('#torrentHeaderMessage').html(
    plugin.escapeHtml(statusText) +
    ((d.msg) ? ' · ' + plugin.escapeHtml(d.msg) : '') +
    ' · ' +
    plugin.escapeHtml(theConverter.bytes(d.size, 2))
  );

  $('#torrentDetails #status td:last').text(statusText + ' ').append('<button class="btn btn-default btn-sm" type="button" onclick="mobile.recheck();" title="Recheck">↻</button>');
  $('#torrentPriority option').prop('selected', false);
  $('#torrentPriority option[value=' + d.priority + ']').prop('selected', true);
  if (this.ratioGroupsLoaded) {
    $('#torrentRatioGrp option').prop('selected', false);
    if (d.ratiogroup) {
      $('#torrentRatioGrp option[value=' + d.ratiogroup.replace(/.*rat_/,'') + ']').prop('selected', true);
    } else {
      $('#torrentRatioGrp option[value=-1]').prop('selected', true);
    }
  }
  if (this.throttleLoaded) {
    $('#torrentChannel option').prop('selected', false);
    if (d.throttle) {
      $('#torrentChannel option[value=' + d.throttle.replace('thr_','') + ']').prop('selected', true);
    } else {
      $('#torrentChannel option[value=-1]').prop('selected', true);
    }
  }
  this.fillLabel(d.label);
  $('#torrentDetails #done td:last').text(percent + '%');
  $('#torrentDetails #downloaded td:last').text(theConverter.bytes(d.downloaded,2));
  $('#torrentDetails #size td:last').text(theConverter.bytes(d.size,2));
  $('#torrentDetails #remaining td:last').text(theConverter.bytes(d.remaining,2));
  $('#torrentDetails #timeElapsed td:last').text(theConverter.time(Math.floor((new Date().getTime()-theWebUI.deltaTime)/1000-iv(d.state_changed)),true));
  $('#torrentDetails #created td:last').text((d.created>3600*24*365) ? theConverter.date(iv(d.created)+theWebUI.deltaTime/1000) : "");
  if (this.seedingtimeLoaded) {
    $('#torrentDetails #seedtime td:last').text((d.seedingtime>3600*24*365) ? theConverter.time(new Date().getTime()/1000-(iv(d.seedingtime)+theWebUI.deltaTime/1000),true) : "");
    $('#torrentDetails #dateAdded td:last').text((d.addtime>3600*24*365) ? theConverter.date(iv(d.addtime)+theWebUI.deltaTime/1000) : "");
  }
  $('#torrentDetails #eta td:last').html((d.eta ==- 1) ? "&#8734;" : theConverter.time(d.eta));
  $('#torrentDetails #ratio td:last').html((d.ratio ==- 1) ? "&#8734;" : theConverter.round(d.ratio/1000,3));
  $('#torrentDetails #downloadSpeed td:last').text(theConverter.speed(d.dl));
  $('#torrentDetails #wasted td:last').text(theConverter.bytes(d.skip_total,2));
  $('#torrentDetails #uploaded td:last').text(theConverter.bytes(d.uploaded,2));
  $('#torrentDetails #uploadSpeed td:last').text(theConverter.speed(d.ul));
  $('#torrentDetails #seeds td:last').text(d.seeds_actual + " " + theUILang.of + " " + d.seeds_all + " " + theUILang.connected);
  $('#torrentDetails #peers td:last').text(d.peers_actual + " " + theUILang.of + " " + d.peers_all + " " + theUILang.connected);
  $('#torrentDetails #savePath td:last').text(d.save_path);
  $('#torrentDetails #comment td:last').text(d.comment);
  $('#torrentDetails #trackerStatus td:last').text(d.msg);
};

plugin.changePriority = function() {
  this.request('?action=dsetprio&v=' + $('#torrentPriority').val() + '&hash=' + this.torrent.hash);
};

plugin.changeRatioGrp = function() {
  this.request('?action=setratio&v=' + $('#torrentRatioGrp').val() + '&hash=' + this.torrent.hash);
};

plugin.changeChannel = function() {
  this.request('?action=setthrottle&v=' + $('#torrentChannel').val() + '&hash=' + this.torrent.hash);
};

plugin.editLabel = function() {
  plugin.labelInEdit = true;
  $('#torrentDetails #label td:last')
  .html('<div class="input-append">' +
  '<input class="form-control" id="labelEdit" type="text" value="' + plugin.escapeAttr(plugin.torrent.label) +'"/>' +
  '<button class="btn btn-default btn-sm" type="button">✓</button></div>');
  $('#labelEdit').focus();
  $('#labelEdit').blur(function() {
    var newLabel = $('#labelEdit').val();
    plugin.labelInEdit = false;
    plugin.fillLabel(newLabel);

    if (plugin.torrent.label != newLabel) {
      plugin.torrent.label = newLabel;
      plugin.torrents[plugin.torrent.hash].label = newLabel;

      plugin.request('?action=setlabel&hash=' + plugin.torrent.hash + '&s=label&v=' + encodeURIComponent(newLabel));
    };
  });
};

plugin.showDetails = function(e) {
  this.torrent = this.torrents[e];
  if (this.torrent == undefined)
  return;

  this.torrent.hash = e;
  var d = this.torrent;

  this.fillDetails(d);

  this.showPage('torrentDetails');
  setTimeout(function() {
    var totalWidth = $('#torrentDetails').width();
    var combinedWidth = $('#detailsDetailsPage #priority td:nth-child(1)').outerWidth(true);
    var tdExcess = $('#detailsDetailsPage #priority td:nth-child(2)').outerWidth(true) - $('#detailsDetailsPage #priority td:nth-child(2)').width();
    var diffWidth = totalWidth - combinedWidth - tdExcess;
    $('#torrentDetails select').css('max-width',diffWidth);
  }, 0);
  $('.torrentControl').css('display', '');
  this.showDetailsInDetails();
};

plugin.showDetailsInDetails = function() {
  $('.detailsPage').css('display', 'none');
  $('#detailsDetailsPage').css('display', '');
  $('#detailsNav li').removeClass('active');
  $('#detailsDetailsTab').addClass('active');
};

plugin.showTrackersInDetails = function() {
  $('.detailsPage').css('display', 'none');
  $('#detailsTrackersPage').css('display', '');
  $('#detailsNav li').removeClass('active');
  $('#detailsTrackers').addClass('active');
  this.renderDetailsPlaceholder('#detailsTrackersPage', 'Loading trackers', 'Fetching tracker health and scrape information.');
  this.loadTrackers();
}

plugin.showFilesInDetails = function() {
  $('.detailsPage').css('display', 'none');
  $('#detailsFilesPage').css('display', '');
  $('#detailsNav li').removeClass('active');
  $('#detailsFiles').addClass('active');
  this.renderDetailsPlaceholder('#detailsFilesPage', 'Loading files', 'Building the directory tree and file priorities.');
  this.loadFiles();
}

plugin.showPeersInDetails = function() {
  $('.detailsPage').css('display', 'none');
  $('#detailsPeersPage').css('display', '');
  $('#detailsNav li').removeClass('active');
  $('#detailsPeers').addClass('active');
  $('#peersTable tbody').html('<tr><td colspan="10" class="py-4 text-center text-zinc-500">Loading peers…</td></tr>');
  this.loadPeers();
}

plugin.toogleTrackerInfo = function(s) {
  this.toogleDisplay($(s).parent().find('div'));
}

plugin.loadTrackers = function() {
  if (this.torrent != undefined) {
    var hash = this.torrent.hash;
    this.request('?action=gettrackers&hash=' + hash, function(data) {
      var trackers = data[hash] || [];
      if (hash == mobile.torrent.hash) {
        if (!trackers.length) {
          mobile.renderDetailsPlaceholder('#detailsTrackersPage', 'No trackers available', 'This torrent does not currently expose tracker details.');
          return;
        }
        var trackersHtml = '<div class="panel-group" id="trackersAccordion">';

        for (var i = 0; i < trackers.length; i++) {
          trackersHtml +=
          '<div class="panel panel-default"><div class="panel-heading">' +
          '<a class="accordion-toggle" data-toggle="collapse" data-parent="#trackersAccordion" href="#tracker' + i + '">' +
          plugin.escapeHtml(trackers[i].name) + '</a></div>' +
          '<div id="tracker' + i + '" class="panel-collapse collapse"><div class="panel-body">' +
          '<table class=" table table-striped"><tbody>' +
          '<tr><td>' + theUILang.Type + '</td><td>' + plugin.escapeHtml(theFormatter.trackerType(trackers[i].type)) + '</td></tr>' +
          '<tr><td>' + theUILang.Enabled + '</td><td>' + plugin.escapeHtml(theFormatter.yesNo(trackers[i].enabled)) + '</td></tr>' +
          '<tr><td>' + theUILang.Group + '</td><td>' + plugin.escapeHtml(trackers[i].group) + '</td></tr>' +
          '<tr><td>' + theUILang.Seeds + '</td><td>' + plugin.escapeHtml(trackers[i].seeds) + '</td></tr>' +
          '<tr><td>' + theUILang.Peers + '</td><td>' + plugin.escapeHtml(trackers[i].peers) + '</td></tr>' +
          '<tr><td>' + theUILang.scrapeDownloaded + '</td><td>' + plugin.escapeHtml(trackers[i].downloaded) + '</td></tr>' +
          '<tr><td>' + theUILang.scrapeUpdate + '</td><td>' +
          plugin.escapeHtml(trackers[i].last ? theConverter.time($.now() / 1000 - trackers[i].last - theWebUI.deltaTime / 1000, true) : '') +
          '</td></tr>' +
          '<tr><td>' + theUILang.trkInterval + '</td><td>' + plugin.escapeHtml(theConverter.time(trackers[i].interval)) + '</td></tr>' +
          '<tr><td>' + theUILang.trkPrivate + '</td><td>' + plugin.escapeHtml(theFormatter.yesNo(theWebUI.trkIsPrivate(trackers[i].name))) + '</td></tr>' +
          '</tbody></table></div></div></div>';
        }

        trackersHtml += '</div>';
        $('#detailsTrackersPage').html(trackersHtml);

        if (!plugin.bootstrapJS) {
          $('#trackersAccordion a').click(function() {
            $('#trackersAccordion .in').removeClass('in');
            $(this).parent().parent().find('.panel-body').addClass('in');
            return false;
          });
        }
      }
    });
  }
};

plugin.loadPeers = function() {
  if (this.torrent != undefined) {
    var hash = this.torrent.hash;
    this.request('?action=getpeers&hash=' + hash, function(data) {
      var peers = data;
      var pid = Object.keys(peers);
      if (hash == mobile.torrent.hash) {
        if (!pid.length) {
          $('#peersTable tbody').html('<tr><td colspan="10" class="py-4 text-center text-zinc-500">No peer information available for this torrent right now.</td></tr>');
          return;
        }
        var tableHeight = $(window).height() - $('#mainNavbar').outerHeight(true) - ($('#torrentDetails .nav').outerHeight(true) + $('#torrentDetailsHeader').outerHeight(true) + ($('#torrentDetailsHeader #torrentProgress').outerHeight(true) - $('#torrentDetailsHeader #torrentProgress').outerHeight()));
        $('div.tableFixHead').css("max-height", tableHeight + "px");
        
        var peersHtml = '';

        for (var i = 0; i < pid.length; i++) {
          peersHtml += '<tr>' +
          '<td>' + plugin.escapeHtml(peers[pid[i]].ip + ':' +  peers[pid[i]].port) + '</td>' +
          '<td>' + plugin.escapeHtml(peers[pid[i]].version) + '</td>' +
          '<td>' + plugin.escapeHtml(peers[pid[i]].flags) + '</td>' +
          '<td>' + plugin.escapeHtml(peers[pid[i]].done + '%') + '</td>' +
          '<td>' + plugin.escapeHtml(theConverter.bytes(peers[pid[i]].downloaded,2)) + '</td>' +
          '<td>' + plugin.escapeHtml(theConverter.bytes(peers[pid[i]].uploaded,2)) + '</td>' +
          '<td>' + plugin.escapeHtml(theConverter.speed(peers[pid[i]].dl)) + '</td>' +
          '<td>' + plugin.escapeHtml(theConverter.speed(peers[pid[i]].ul)) + '</td>' +
          '<td>' + plugin.escapeHtml(theConverter.speed(peers[pid[i]].peerdl)) + '</td>' +
          '<td>' + plugin.escapeHtml(theConverter.bytes(peers[pid[i]].peerdownloaded,2)) + '</td>' +
          '</tr>';
        }

        $('#peersTable tbody').html(peersHtml);
      }
    });
  }
};

plugin.files = undefined;

plugin.getDir = function(p) {
  var path = p.split('/');
  if ((path[0] == '') && (path.length == 1)) {
    path = [];
  }

  var dir = plugin.files;
  var realPath = '';
  for (var i = 0; i < path.length; i++) {
    if (path[i] == '') {
      continue;
    }

    if (dir.container[path[i]] != undefined) {
      dir = dir.container[path[i]];
      realPath += '/' + path[i];
      if (!dir.directory) {
        break;
      }
    } else {
      break;
    }
  }

  realPath = realPath.substr(1);
  return [realPath, dir];
}

plugin.getFilesList = function(s) {
  var ret = '';

  for (var name in s) {
    if (s[name].directory) {
      ret += this.getFilesList(s[name].container);
    } else {
      ret += '&v=' + s[name].id;
    }
  }

  return ret;
}

plugin.drawFiles = function(p) {
  var vars = this.getDir(p);
  var realPath = vars[0];
  var dir = vars[1];

  var filesHtml = '';

  if (!dir.root) {
    var i = realPath.lastIndexOf('/');
    if (i < 0) {
      i = 0;
    }
    var upperDir = realPath.substr(0, i);
    filesHtml += '<a href="javascript://void();" onclick="mobile.drawFiles(\'' + plugin.escapeJsString(upperDir) + '\');">' +
    '📁 ..</a><hr>';
  }

  for (var name in dir.container) {
    filesHtml += '<div>' +
    '<div class="hiddenPath">' + plugin.escapeHtml(realPath + '/' + name) + '</div>' +
    '<button onclick="mobile.toogleDisplay($(this).parent().find(\'.prioritySelect\'));" class="btn btn-default btn-sm pull-right" title="Priority">☰</button>'
    if (dir.container[name].directory) {
      filesHtml += '<a href="javascript://void();" onclick="mobile.drawFiles(\'' + plugin.escapeJsString(realPath + '/' + name) + '\');">' +
      '📁&nbsp;' + plugin.escapeHtml(name) + '</a>';
    } else {
      var idName = 'file' + dir.container[name].id;
      filesHtml += '<a href="javascript://void();" onclick="mobile.toogleDisplay($(\'#' + idName + '\'));">' +
      '📄&nbsp;' + plugin.escapeHtml(name) + '</a><div style="display:none;" id="' + idName + '">' +
      '<table class="table table-striped"><tbody>' +
      '<tr><td>' + theUILang.Done + '</td><td>' + plugin.escapeHtml(theConverter.bytes(dir.container[name].done)) + '</td></tr>' +
      '<tr><td>' + theUILang.Size + '</td><td>' + plugin.escapeHtml(theConverter.bytes(dir.container[name].size)) + '</td></tr>' +
      '</tbody></table></div>';
    }
    filesHtml += '<select class="prioritySelect" style="display:none;">' +
    '<option disabled ' + ((dir.container[name].priority == -1) ? 'selected' : '') + '></option>' +
    '<option value="2" ' + ((dir.container[name].priority == 2) ? 'selected' : '') + '>' + theUILang.High_priority + '</option>' +
    '<option value="1" ' + ((dir.container[name].priority == 1) ? 'selected' : '') + '>' + theUILang.Normal_priority + '</option>' +
    '<option value="0" ' + ((dir.container[name].priority == 0) ? 'selected' : '') + '>' + theUILang.Dont_download + '</option>' +
    '</select></div><hr/>';

  }

  $('#detailsFilesPage').html(filesHtml);
  $('#detailsFilesPage select').change(function() {
    var newValue = $(this).val();
    if (newValue < 0) {
      return;
    }

    var vars = plugin.getDir($(this).parent().find('.hiddenPath').text());

    var filesList = '';
    if (!vars[1].directory) {
      filesList = vars[1].id;
    } else {
      filesList = plugin.getFilesList(vars[1].container);
    }

    plugin.request('?action=setprio&hash=' + plugin.torrent.hash  + '&v=' +filesList + '&s=' + newValue);
  });
}

plugin.fillDirectoriesPriority = function(p) {
  var priority = -2;
  for (var name in p.container) {
    if (p.container[name].directory) {
      this.fillDirectoriesPriority(p.container[name]);
    }
    if (priority == -2) {
      priority = p.container[name].priority;
    } else if (priority != p.container[name].priority) {
      priority = -1;
    }
  }
  p.priority = priority;
}

plugin.loadFiles = function() {
  if (this.torrent != undefined) {
    var hash = this.torrent.hash;
    $('#detailsFilesPage').html('');
    this.request('?action=getfiles&hash=' + hash, function(data) {
      if (!mobile.torrent || hash != mobile.torrent.hash) {
        return;
      }
      var rawFiles = data[hash] || [];
      if (!rawFiles.length) {
        mobile.renderDetailsPlaceholder('#detailsFilesPage', 'No file tree available', 'ruTorrent did not return any file metadata for this torrent.');
        return;
      }
      var files = {root: true, directory: true, priority: -1, container: {}};

      for (var i = 0; i < rawFiles.length; i++) {
        var path = rawFiles[i].name.replace(/^\/|\/$/g, '').split('/');
        var currDir = files;
        for (var j = 0; j < path.length -1; j++) {
          if (currDir.container[path[j]] == undefined) {
            currDir.container[path[j]] = {directory: true, root: false, container: {}, priority: -2};
          }
          currDir = currDir.container[path[j]];
        }
        currDir.container[path[path.length - 1]] = {root: false,
          directory: false,
          size: rawFiles[i].size,
          done: rawFiles[i].done,
          priority: rawFiles[i].priority,
          id: i
        };
      }

      plugin.fillDirectoriesPriority(files);
      mobile.files = files;
      mobile.drawFiles('');
    });
  }
}

plugin.start = function() {
  if (this.torrent != undefined) {
    var status = this.torrent.state;

    if ((!(status & dStatus.started) || (status & dStatus.paused) && !(status & dStatus.checking) && !(status & dStatus.hashing))) {
      this.request('?action=start&hash=' + this.torrent.hash);
    }
  }
};

plugin.stop = function() {
  if (this.torrent != undefined) {
    var status = this.torrent.state;

    if ((status & dStatus.started) || (status & dStatus.hashing) || (status & dStatus.checking)) {
      this.request('?action=stop&hash=' + this.torrent.hash);
    }
  }
};

plugin.pause = function() {
  if (this.torrent != undefined) {
    var status = this.torrent.state;

    if (((status & dStatus.started) && !(status & dStatus.paused) && !(status & dStatus.checking) && !(status & dStatus.hashing))) {
      this.request('?action=pause&hash=' + this.torrent.hash);
    } else if (((status & dStatus.paused) && !(status & dStatus.checking) && !(status & dStatus.hashing))) {
      this.request('?action=unpause&hash=' + this.torrent.hash);
    }
  }
};

plugin.recheck = function() {
  if (this.torrent != undefined) {
    var status = this.torrent.state;

    if (!(status & dStatus.checking) && !(status & dStatus.hashing)) {
      this.request('?action=recheck&hash=' + this.torrent.hash);
    }
  }
};

plugin.delete = function() {
  if (this.torrent == undefined) {
    this.showList();
  } else {

    if ((this.eraseWithDataLoaded) && (this.eraseWithDataDefault != undefined)) {
      $('#deleteWithData input').prop('checked', this.eraseWithDataDefault);
    }
    if (theWebUI.settings["webui.confirm_when_deleting"]) {
      $('#confimTorrentDelete h5').html('<span id="confirmText">' + theUILang.Rem_torrents_prompt + '</span><hr />' + this.torrent.name);
      this.showPage('confimTorrentDelete');
    } else {
      this.deleteConfimed();
    }
  }
};

plugin.deleteConfimed = function() {
  if ((this.eraseWithDataLoaded) && ($('#deleteWithData input').prop('checked'))) {
    this.request('?action=removewithdata&hash=' + this.torrent.hash);
  } else {
    this.request('?action=remove&hash=' + this.torrent.hash);
  }
  this.torrent = undefined;
  this.showList();
};

plugin.chooseGetDir = function(path) {
  $('#' + plugin.getDirTargetInput).val(path);
  history.go(-1);
}

plugin.drawGetDir = function(path, first) {
  var dirParam = path !== undefined && path !== null ? String(path) : '';
  $.ajax({
    url: 'plugins/_getdir/listdir.php',
    data: {
      dir: dirParam,
      time: new Date().getTime()
    },
    dataType: 'json',
    cache: false,
    success: function(res) {
      if (!res || !$.isArray(res.directories)) {
        plugin.showAlert('listdir: invalid response', 'alert-danger');
        return;
      }
      var cur = res.path || '';
      var $wrap = $('<div class="page-card p-4"></div>');
      var $header = $('<div class="section-header compact"></div>');
      $header.append(
        $('<div></div>').append(
          $('<div class="mobile-eyebrow"></div>').text('Directory browser'),
          $('<h2 class="page-heading"></h2>').text(cur || '/'),
          $('<p class="page-copy"></p>').text('Choose where new torrents should be saved.')
        )
      );
      $wrap.append($header);

      var $table = $('<table class="table table-striped mb-0 mt-4"></table>');
      var $tbody = $('<tbody></tbody>');
      $.each(res.directories, function(_, name) {
        var $tr = $('<tr class="get-dir-entry"></tr>');
        $tr.append($('<td></td>').text('📁 ' + name));
        var nextPath = cur + name;
        $tr.on('click', function() {
          mobile.drawGetDir(nextPath, false);
        });
        $tbody.append($tr);
      });
      $table.append($tbody);
      $wrap.append($table);

      var $footer = $('<div class="action-row"></div>');
      var $ok = $('<button type="button" class="btn btn-primary"></button>').text(theUILang.ok);
      $ok.on('click', function() {
        mobile.chooseGetDir(cur);
      });
      var $cancel = $('<button type="button" class="btn btn-default"></button>').text(theUILang.Cancel);
      $cancel.on('click', function() {
        history.go(-1);
      });
      $footer.append($ok, $cancel);
      $wrap.append($footer);

      $('#getDirList').empty().append($wrap);
      if (first === true) {
        mobile.showPage('getDirList');
      }
    },
    error: function(xhr) {
      var msg = theUILang.Error || 'Error';
      if (xhr && xhr.status === 404) {
        msg += ' (404)';
      }
      plugin.showAlert(msg, 'alert-danger');
    }
  });
};

plugin.showGetDir = function() {
  plugin.getDirTargetInput = arguments[0] || 'dir_edit';
  this.drawGetDir('', true);
};

plugin.startCreateTorrent = function() {
  var path = $.trim($('#create_path_edit').val());
  if (!path.length) {
    plugin.showAlert('Choose a file or directory first.', 'alert-danger');
    return false;
  }

  var payload = {
    cmd: 'create',
    path_edit: path,
    trackers: $('#create_trackers').val() || '',
    piece_size: $('#create_piece_size').val(),
    comment: $('#create_comment').val() || '',
    source: $('#create_source').val() || '',
    private: $('#create_private').prop('checked') ? 1 : 0,
    start_seeding: $('#create_start_seeding').prop('checked') ? 1 : 0,
    hybrid: $('#create_hybrid').prop('checked') ? 1 : 0
  };

  $('#createTorrentSubmit').prop('disabled', true);
  plugin.setCreateTaskState(
    'page-callout-muted',
    'Creating torrent',
    'ruTorrent is building the torrent metadata. This can take a moment for large directories.',
    false
  );

  $.ajax({
    url: 'plugins/create/action.php',
    type: 'POST',
    dataType: 'json',
    data: payload,
    success: function(task) {
      var errors = (task && task.errors) ? task.errors.filter(Boolean) : [];
      if (!task || task.no == null || task.no < 0 || errors.length) {
        $('#createTorrentSubmit').prop('disabled', false);
        plugin.setCreateTaskState(
          'page-callout-danger',
          'Create torrent failed',
          errors.join(' ') || 'ruTorrent could not start the create task.',
          false
        );
        plugin.showAlert(errors.join(' ') || 'Could not start create torrent task.', 'alert-danger');
        return;
      }
      plugin.createTask = { no: task.no };
      plugin.pollCreateTask();
    },
    error: function() {
      $('#createTorrentSubmit').prop('disabled', false);
      plugin.setCreateTaskState(
        'page-callout-danger',
        'Create torrent failed',
        'The mobile UI could not contact the create plugin endpoint.',
        false
      );
      plugin.showAlert('Could not contact the create plugin endpoint.', 'alert-danger');
    }
  });

  return false;
};

plugin.pollCreateTask = function() {
  if (!plugin.createTask) {
    return;
  }
  $.ajax({
    url: 'plugins/_task/action.php',
    type: 'GET',
    dataType: 'json',
    data: {
      cmd: 'check',
      no: plugin.createTask.no
    },
    success: function(task) {
      var errors = (task && task.errors) ? task.errors.filter(Boolean) : [];
      if (!task || task.status == null) {
        $('#createTorrentSubmit').prop('disabled', false);
        plugin.setCreateTaskState(
          'page-callout-danger',
          'Create torrent failed',
          'The create task returned an unexpected response.',
          false
        );
        return;
      }
      if (task.status < 0) {
        setTimeout(function() {
          plugin.pollCreateTask();
        }, 1200);
        return;
      }

      $('#createTorrentSubmit').prop('disabled', false);
      if (errors.length || task.status !== 0) {
        plugin.setCreateTaskState(
          'page-callout-danger',
          'Create torrent failed',
          errors.join(' ') || 'The create task finished with an error.',
          false
        );
        plugin.showAlert(errors.join(' ') || 'Create torrent failed.', 'alert-danger');
        return;
      }

      plugin.setCreateTaskState(
        'page-callout-success',
        'Torrent ready',
        'The `.torrent` file is ready to download.',
        true
      );
      $('#createDownloadNo').val(plugin.createTask.no);
      plugin.showAlert('Torrent created successfully. Download is ready.', 'alert-success');
    },
    error: function() {
      $('#createTorrentSubmit').prop('disabled', false);
      plugin.setCreateTaskState(
        'page-callout-danger',
        'Create torrent failed',
        'The mobile UI could not read the task status from ruTorrent.',
        false
      );
      plugin.showAlert('Could not read create task status.', 'alert-danger');
    }
  });
};

plugin.downloadCreatedTorrent = function() {
  if (!plugin.createTask) {
    return;
  }
  $('#createDownloadNo').val(plugin.createTask.no);
  $('#createDownloadForm').trigger('submit');
};

plugin.updateLabelDropdown = function () {
  var $menu = plugin.getDropdownMenu('labels', '#torrentsLabels');
  $menu.css('width', '');
  $('#mobileDropdownPortal .mobile-dropdown-menu a, #torrentsList .nav > li > ul a').css('white-space','');
  var totalWidth = $('#torrentsList .nav').width();
  var combinedWidth = $('#torrentsStatus').outerWidth(true);
  var selfWidth = $menu.width();
  var selfExcess = $menu.outerWidth(true) - selfWidth;
  var diffWidth = totalWidth - combinedWidth - selfExcess;
  if (diffWidth < selfWidth && selfWidth > 0 && diffWidth > 0) {
    $menu.width(diffWidth);
    $('#mobileDropdownPortal .mobile-dropdown-menu a, #torrentsList .nav > li > ul a').css('white-space','normal');
  }
};

plugin.updateTrackerDropdown = function () {
  var $menu = plugin.getDropdownMenu('trackers', '#torrentsTrackers');
  $menu.css('width', '');
  $('#mobileDropdownPortal .mobile-dropdown-menu a, #torrentsList .nav > li > ul a').css('white-space','');
  var combinedWidth = $('#torrentsStatus').outerWidth(true) + $('#torrentsLabels').outerWidth(true) + $('#torrentsTrackers').outerWidth(true);
  var selfWidth = $menu.width();
  var selfExcess = $menu.outerWidth(true) - selfWidth;
  var diffWidth = combinedWidth - selfExcess;
  if (diffWidth < selfWidth && selfWidth > 0 && diffWidth > 0) {
    $menu.width(diffWidth);
    $('#mobileDropdownPortal .mobile-dropdown-menu a, #torrentsList .nav > li > ul a').css('white-space','normal');
  }
};

plugin.loadRatio = function () {
  var ratio = thePlugins.get("ratio");
  if (ratio.allStuffLoaded) {
    $('#priority').after('<tr id="ratiogrp"><td></td><td><select id="torrentRatioGrp"></select></td></tr>');
    $('#torrentRatioGrp').change(function(){mobile.changeRatioGrp()});
    var ratioHTML = '<option value="-1">' + theUILang.mnuRatioUnlimited + '</option>'
    $.each(theWebUI.ratios, function(i, v) {
      ratioHTML += '<option value="' + i + '">' + v.name + '</option>';
    });
    $('#torrentRatioGrp').html(ratioHTML);
    $('#ratiogrp').children('td:first').text(theUILang.ratio);
    
    rTorrentStub.prototype.setratio = function()
    {
      for(var i=0; i<this.vs.length; i++)
      {
        var wasNo = plugin.getRatioData(this.hashes[i]);
        if(wasNo!=this.vs[i])
        {
          if(wasNo>=0)
          {
            cmd = new rXMLRPCCommand('view.set_not_visible');
            cmd.addParameter("string",this.hashes[i]);
            cmd.addParameter("string","rat_"+wasNo);
            this.commands.push( cmd );
            cmd = new rXMLRPCCommand('d.views.remove');
            cmd.addParameter("string",this.hashes[i]);
            cmd.addParameter("string","rat_"+wasNo);
            this.commands.push( cmd );
          }
          if(this.vs[i]>=0)
          {
            cmd = new rXMLRPCCommand('d.views.push_back_unique');
            cmd.addParameter("string",this.hashes[i]);
            cmd.addParameter("string","rat_"+this.vs[i]);
            this.commands.push( cmd );
            cmd = new rXMLRPCCommand('view.set_visible');
            cmd.addParameter("string",this.hashes[i]);
            cmd.addParameter("string","rat_"+this.vs[i]);
            this.commands.push( cmd );
          }
        }
      }
    }
  } else {
    setTimeout(function(){plugin.loadRatio()}, 1000);
  }
};

plugin.loadThrottle = function () {
  var throttle = thePlugins.get("throttle");
  if (throttle.allStuffLoaded) {
    $('#priority').after('<tr id="throttle"><td></td><td><select id="torrentChannel"></select></td></tr>');
    $('#torrentChannel').change(function(){mobile.changeChannel()});
    var throttleHTML = '<option value="-1">' + theUILang.mnuUnlimited + '</option>';
    $.each(theWebUI.throttles, function(i, v) {
      throttleHTML += '<option value="' + i + '">' + v.name + '</option>';
    });
    $('#torrentChannel').html(throttleHTML);
    $('#throttle').children('td:first').text(theUILang.throttle);
  
    rTorrentStub.prototype.setthrottle = function()
    {
      for(var i=0; i<this.vs.length; i++)
      {
        var status = theWebUI.getStatusIcon(mobile.torrents[this.hashes[i]]);
        var needRestart = (status[1]==theUILang.Seeding) || (status[1]==theUILang.Downloading);
        var name = (this.vs[i]>=0) ? "thr_"+this.vs[i] : "";
        if(needRestart)
        {
          cmd = new rXMLRPCCommand('d.stop');
          cmd.addParameter("string",this.hashes[i]);
          this.commands.push( cmd );
        }
        cmd = new rXMLRPCCommand('d.set_throttle_name');
        cmd.addParameter("string",this.hashes[i]);
        cmd.addParameter("string",name);
        this.commands.push( cmd );
        if(needRestart)
        {
          cmd = new rXMLRPCCommand('d.start');
          cmd.addParameter("string",this.hashes[i]);
          this.commands.push( cmd );
        }
      }
    }
  } else {
    setTimeout(function(){plugin.loadThrottle()}, 1000);
  }
};

plugin.loadSeedingTime = function () {
  var seedingtime = thePlugins.get("seedingtime");
  if (seedingtime.allStuffLoaded) {
    $('#created').after('<tr id="seedtime"><td></td><td></td></tr>');
    $('#created').after('<tr id="dateAdded"><td></td><td></td></tr>');
    $('#dateAdded').children('td:first').text(theUILang.addTime);
    $('#seedtime').children('td:first').text(theUILang.seedingTime);
  } else {
    setTimeout(function(){plugin.loadSeedingTime()}, 1000);
  }
};

plugin.dynamicSort = function (property) {
  var sortOrder = 1;
  if(property[0] === "-") {
    sortOrder = -1;
    property = property.substr(1);
  }
  return function (a,b) {
    if (typeof a[property] == 'string' || a[property] instanceof String) {
      if (parseInt(a[property])) {
        if (parseInt(b[property])) {
          var result = (parseInt(a[property]) < parseInt(b[property])) ? -1 : (parseInt(a[property]) > parseInt(b[property])) ? 1 : 0;
        } else {
          var result = -1;
        }
      } else if (parseInt(b[property])) {
        var result = 1;
      } else {
        var result = (a[property].toLowerCase() < b[property].toLowerCase()) ? -1 : (a[property].toLowerCase() > b[property].toLowerCase()) ? 1 : 0;
      }
    } else {
      var result = (a[property] < b[property]) ? -1 : (a[property] > b[property]) ? 1 : 0;
    }
    return result * sortOrder;
  }
}

plugin.update = function(singleUpdate) {
  var queueNext = function() {
    if (!singleUpdate) {
      setTimeout(function() { mobile.update(); }, theWebUI.settings['webui.update_interval']);
    }
  };

  if (!singleUpdate && !plugin.torrentsPrev) {
    plugin.setListState('Loading torrents', 'Fetching the latest transfers from ruTorrent.');
  }

  theWebUI.requestWithTimeout(
    "?list=1&getmsg=1",
    function(data) {
      plugin.torrents = data.torrents || {};
      plugin.labelIds = {'': 0};
      plugin.trackerIds = {};

      var torrentArray = [];
      var labelCounts = {'': 0};
      var trackersCount = {};
      var trackersMap = {};
      var tul = 0;
      var tdl = 0;
      var nextLabelId = 1;
      var nextTrackerId = 1;
      var summary = {
        total: 0,
        downloading: 0,
        completed: 0,
        active: 0
      };

      $.each(plugin.torrents, function(n, v) {
        v.hash = n;
        torrentArray.push(v);
        summary.total++;
        if (v.done == 1000) {
          summary.completed++;
        } else {
          summary.downloading++;
        }
        if (v.ul || v.dl) {
          summary.active++;
        }
        var lbl = $.trim(v.label || '');
        if (plugin.labelIds[lbl] == undefined) {
          plugin.labelIds[lbl] = nextLabelId++;
        }
        if (labelCounts[lbl] == undefined) {
          labelCounts[lbl] = 0;
        }
        labelCounts[lbl]++;
      });

      torrentArray.sort(plugin.dynamicSort(plugin.sort));

      mobile.request('?action=getalltrackers', function(allTrackers) {
        var listHtml = $('#torrentsList #list table tbody');
        var listHtmlString = '';
        var labelsHtml =
          '<li><a href="javascript://void();" onclick="mobile.filter(mobile.statusFilter.label, this, \'\');">' +
          theUILang.No_label +
          ' (' + (labelCounts[''] || 0) + ')</a></li>';
        var trackersHtml = '';

        $.each(torrentArray, function(n, v) {
          var status = theWebUI.getStatusIcon(v);
          var trackers = allTrackers[v.hash] || [];
          var uniqueTrackers = [];
          var percent = v.done / 10;

          tul += iv(v.ul);
          tdl += iv(v.dl);

          for (var i = 0; i < trackers.length; i++) {
            var trackerName = theWebUI.getTrackerName(trackers[i].name);
            if (!trackerName || $.inArray(trackerName, uniqueTrackers) !== -1) {
              continue;
            }
            uniqueTrackers.push(trackerName);
            if (trackersCount[trackerName] == undefined) {
              trackersCount[trackerName] = 0;
            }
            trackersCount[trackerName]++;
            if (plugin.trackerIds[trackerName] == undefined) {
              plugin.trackerIds[trackerName] = nextTrackerId++;
            }
          }

          listHtmlString += plugin.renderTorrentRow(v, status[1], percent, uniqueTrackers);
          trackersMap[v.hash] = uniqueTrackers;
        });

        Object.keys(labelCounts).sort(function(a, b) {
          if (a === '') return -1;
          if (b === '') return 1;
          return a.toLowerCase() < b.toLowerCase() ? -1 : 1;
        }).forEach(function(lbl) {
          if (lbl === '') {
            return;
          }
          labelsHtml +=
            '<li><a href="javascript://void();" onclick="mobile.filter(mobile.statusFilter.label, this, \'' +
            plugin.escapeJsString(lbl) +
            '\');">' +
            plugin.escapeHtml(lbl) +
            ' (' + labelCounts[lbl] + ')</a></li>';
        });

        Object.keys(trackersCount).sort().forEach(function(t) {
          trackersHtml +=
            '<li><a href="javascript://void();" onclick="mobile.filter(mobile.statusFilter.tracker, this, \'' +
            plugin.escapeJsString(t) +
            '\');">' +
            plugin.escapeHtml(t) +
            ' (' + trackersCount[t] + ')</a></li>';
        });

        plugin.getDropdownMenu('labels', '#torrentsLabels').html(labelsHtml);
        plugin.getDropdownMenu('trackers', '#torrentsTrackers').html(trackersHtml);
        listHtml.html(listHtmlString);

        $.each(trackersMap, function(id, ns) {
          $.each(ns, function(i, trackerName) {
            $('#' + id).addClass('tracker' + plugin.trackerIds[trackerName]);
          });
        });

        $('#torrentsAll > a').text(theUILang.All + ' (' + summary.total + ')');
        $('#torrentsDownloading > a').text(theUILang.Downloading + ' (' + summary.downloading + ')');
        $('#torrentsCompleted > a').text(theUILang.Finished + ' (' + summary.completed + ')');
        $('#torrentsActive > a').text(theUILang.Active + ' (' + summary.active + ')');
        $('#torrentsInactive > a').text(theUILang.Inactive + ' (' + (summary.total - summary.active) + ')');
        $('#torrentsError > a').text(theUILang.Error + ' (' + $('.errorYes').length + ')');

        plugin.updateSummaryCards(summary);
        plugin.lastUpdatedAt = new Date();
        plugin.updateLastUpdatedLabel();
        $('#upspeed').text(theConverter.speed(tul));
        $('#downspeed').text(theConverter.speed(tdl));
      plugin.updateSpeedVisibility();
      plugin.syncLayoutMetrics();

        plugin.torrentsPrev = plugin.torrents;
        plugin.filter(plugin.currFilter, undefined, plugin.navFilter);

        if (plugin.torrent != undefined) {
          if (plugin.torrents[plugin.torrent.hash] != undefined) {
            plugin.torrent = plugin.torrents[plugin.torrent.hash];
            plugin.fillDetails(plugin.torrent);
            plugin.loadPeers();
          } else {
            plugin.showList();
          }
        }

        queueNext();
      });
    },
    function() {
      plugin.setListState('Refresh timed out', 'ruTorrent did not answer in time. Try again in a moment.');
      queueNext();
    },
    function(status, text) {
      plugin.setListState('Could not refresh torrents', 'There was a problem contacting ruTorrent.');
      queueNext();
    }
  );
};

plugin.disableOthers = function() {
  var href = window.location.href;
  var start =
    href.indexOf("mobile=1") >= 0 ||
    href.indexOf("mobile%3D1") >= 0;

  if (!start && this.enableAutodetect) {
    start = jQuery.browser.mobile;
  }

  if (start) {
    dxSTable.prototype.renameColumn = function(no,name) { }

    dxSTable.prototype.Sort = function(e) { }

    dxSTable.prototype.createRow = function(cols, sId, icon, attr) { }

    dxSTable.prototype.addRow = function (cols, sId, icon, attr) { }

    dxSTable.prototype.addRowById = function (ids, sId, icon, attr) { }

    dxSTable.prototype.refreshRows = function( height, fromScroll ) { }

    dxSTable.prototype.getAttr = function (row, attrName) { }
    
    dxSTable.prototype.setAttr = function(row, attr) { }
    
    dxSTable.prototype.setIcon = function(row, icon) { }

    theWebUI.filterByLabel = function() { }

    theWebUI.loadTorrents = function() { }

    $.each(thePlugins.list, function(i, v) {
      if (v.name != 'rpc' && v.name != 'httprpc' && v.name != '_getdir' && v.name != '_task' && v.name != 'create' && v.name != 'throttle' && v.name != 'ratio' && v.name != 'erasedata' && v.name != 'seedingtime' && v.name != 'mobile') {
        v.disable();
      }
    });

    plugin.config = theWebUI.config;
    theWebUI.config = function(data)
    {
    	plugin.config.call(this,data);
    	plugin.init();
    };
  } else {
    this.disable();
  }
};

plugin.init = function() {
  if (plugin._mobileAjaxStarted) {
    return;
  }
  plugin._mobileAjaxStarted = true;

  this.lastHref = window.location.href;

  $(window).off('hashchange.mobile').on('hashchange.mobile', function() {
    plugin.backListener();
  });

  var jQueryVer = jQuery.fn.jquery.split('.');
  if ((jQueryVer[0] == 1) && (jQueryVer[1] >= 7)) {
    this.bootstrapJS = true;
  } else if (jQueryVer[0] > 1) {
    this.bootstrapJS = true;	//For future =)
  }

  $.ajax({
    type: 'GET',
    url: this.path + 'mobile.html',
    processData: false,

    error: function(XMLHttpRequest, textStatus, errorThrown) {
      //TODO: Error
    },

    success: function(data, textStatus) {
      $('body').html(data);

      $('link[rel=stylesheet]').remove();
      plugin.loadLang();
      plugin.loadCSS('appbox');
      plugin.loadMainCSS();
      plugin.initTheme();
      plugin.initChromeState();
      $('head').append('<meta name="apple-mobile-web-app-capable" content="yes" />');
      if (plugin.bootstrapJS)
      injectScript(plugin.path+'js/bootstrap.min.js');

      if (!plugin.bootstrapJS) {
        $('#torrentsStatus > a').click(function(){
          var menu = $('#torrentsStatus');

          if (menu.hasClass('open')) {
            menu.removeClass('open');
          } else {
            menu.addClass('open');
          }
        });
        $('#torrentsStatus > ul').click(function() {
          $('#torrentsStatus').removeClass('open');
        });

        $('#torrentsLabels > a').click(function(){
          var menu = $('#torrentsLabels');

          if (menu.hasClass('open')) {
            menu.removeClass('open');
          } else {
            menu.addClass('open');
          }
        });
        $('#torrentsLabels > ul').click(function() {
          $('#torrentsLabels').removeClass('open');
        });

        $('#torrentsTrackers > a').click(function(){
          var menu = $('#torrentsTrackers');

          if (menu.hasClass('open')) {
            menu.removeClass('open');
          } else {
            menu.addClass('open');
          }
        });
        $('#torrentsTrackers > ul').click(function() {
          $('#torrentsTrackers').removeClass('open');
        });
      }
      
      $('#torrentsLabels > a').click(function(){
        plugin.updateLabelDropdown();
      });
      
      $('#torrentsTrackers > a').click(function(){
        plugin.updateTrackerDropdown();
      });

      $('#mainNavbar').addClass('navbar-fixed-bottom');
      $('#torrentsTopBar').addClass('navbar-fixed-top');
      $(window).off('resize.mobileLayout').on('resize.mobileLayout', function() {
        plugin.syncLayoutMetrics();
      });

      $('.torrentControl').css('display', 'none');

      $('#dlLimit').change(function(){plugin.setDLLimit();});
      $('#ulLimit').change(function(){plugin.setULLimit();});
      $('#torrentSearch').on('input', function() {
        plugin.searchTerm = $(this).val() || '';
        $('#clearSearch').css('display', plugin.searchTerm.length ? '' : 'none');
        plugin.applySearchFilter();
      });
      $('#clearSearch').css('display', 'none');
      plugin.updateLastUpdatedLabel();
      plugin.syncSummaryCardState();
      plugin.updateSpeedVisibility();
      plugin.initDropdownPortals();
      setTimeout(function() {
        plugin.syncLayoutMetrics();
      }, 0);

      $('input[id=torrent_file]').change(function() {
        var v = $(this).val() || '';
        var base = v.replace(/^.*[\\/]/, '');
        $('#torrentFileChosen').text(base);
      });
      $('#createTorrentForm').on('submit', function() {
        return plugin.startCreateTorrent();
      });
      var pieceSizeArray = [32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536];
      var pieceSizeHtml = '';
      for (var p = 0; p < pieceSizeArray.length; p++) {
        var size = pieceSizeArray[p];
        pieceSizeHtml += '<option value="' + size + '"' + (size === 1024 ? ' selected' : '') + '>' +
          ((size < 1024) ? (size + ' KB') : ((size / 1024) + ' MB')) +
          '</option>';
      }
      $('#create_piece_size').html(pieceSizeHtml);

      $('#notAddPath').append(' ' + theUILang.Dont_add_tname);
      $('#startStopped').append(' ' + theUILang.Dnt_start_down_auto);
      $('#fastResume').append(' ' + theUILang.doFastResume);
      $('#randomizeHash').append(' ' + theUILang.doRandomizeHash);
      $('#torrentFileSend').text(theUILang.add_button);

      $('#torrentPriority').html(
        '<option value="3">' + theUILang.High_priority + '</option>' +
        '<option value="2">' + theUILang.Normal_priority + '</option>' +
        '<option value="1">' + theUILang.Low_priority + '</option>' +
        '<option value="0">' + theUILang.Dont_download + '</option>'
      );
      $('#torrentPriority').change(function(){mobile.changePriority()});

      var makeAddRequest = function(frm)
      {
        var s = theURLs.AddTorrentURL+"?";
        if($("#torrents_start_stopped").prop("checked")) {
          s += 'torrents_start_stopped=1&';
        }
        if($("#fast_resume").prop("checked")) {
          s += 'fast_resume=1&';
        }
        if($("#not_add_path").prop("checked")) {
          s += 'not_add_path=1&';
        }
        if($("#randomize_hash").prop("checked")) {
          s += 'randomize_hash=1&';
        }
        var dir = $.trim($("#dir_edit").val());
        if(dir.length) {
          s += ('dir_edit='+encodeURIComponent(dir)+'&');
        }
        var lbl = $.trim($("#tadd_label").val());
        if(lbl.length) {
          s += ('label='+encodeURIComponent(lbl));
        }
        frm.action = s;
        return(true);
      }
      $("#addTorrentFile").submit(function()
      {
        if(!$("#torrent_file").val().match(".torrent")) {
          plugin.showAlert(theUILang.Not_torrent_file,"alert-danger");
          return(false);
        }
        plugin.createiFrame();
        return(makeAddRequest(this));
      });
      $("#addTorrentUrl").submit(function() {
        plugin.createiFrame();
        return(makeAddRequest(this));
      });

      if (thePlugins.isInstalled('erasedata')) {
        $('#confimTorrentDelete h5').after(
          '<div class="checkbox"><label id="deleteWithData">' +
          '<input type="checkbox"> ' + theUILang.Delete_data + '</label></div>');

          plugin.eraseWithDataLoaded = true;
        }
        
        if (thePlugins.isInstalled('throttle')) {
          plugin.throttleLoaded = true;
          plugin.loadThrottle();
        }
        
        if (thePlugins.isInstalled('ratio')) {
          plugin.ratioGroupsLoaded = true;
          plugin.loadRatio();
        }

        if (thePlugins.isInstalled('_getdir')) {
          plugin.getDirLoaded = true;
          $('#dirEditBlock').append('<input type="button" class="btn btn-default btn-sm" id="showGetDir" type="button" onclick="mobile.showGetDir(\'dir_edit\');" value="..."></input>');
          $('#createDirEditBlock').append('<input type="button" class="btn btn-default btn-sm" id="showCreateGetDir" type="button" onclick="mobile.showGetDir(\'create_path_edit\');" value="..."></input>');
        }
        
        if (thePlugins.isInstalled('seedingtime')) {
          plugin.seedingtimeLoaded = true;
          plugin.loadSeedingTime();
        }
        if (!thePlugins.isInstalled('create')) {
          $('#openCreateTorrent').prop('disabled', true).text('Create unavailable');
          $('#createTorrentForm :input').prop('disabled', true);
          plugin.setCreateTaskState(
            'page-callout-danger',
            'Create plugin unavailable',
            'The ruTorrent create plugin is not installed in this environment.',
            false
          );
        } else {
          plugin.setCreateTaskState(
            'page-callout-muted',
            'Ready to create',
            'Choose a path, add trackers, and submit to build a new `.torrent` file.',
            false
          );
        }
        plugin.update();
      }
  });
};

plugin.onLangLoaded = function() {
  $('#torrentsStatus > a > span').html(theUILang.All);
  $('#torrentsLabels > a > span').html(theUILang.Labels);
  $('#torrentsTrackers > a > span').html(theUILang.Trackers);

  $('#detailsDetailsTab a').text(theUILang.General);
  $('#detailsTrackers a').text(theUILang.Trackers);
  $('#detailsFiles a').text(theUILang.Files);
  $('#detailsPeers a').text(theUILang.Peers);

  $('#torrentDetails table tr').each(function(n, v) {
    $(v).children('td:first').text(theUILang[detailsIdToLangId[v.id]]);
  });

  $('#dlLimit').parent().children('label').children('h5').text(theUILang.Glob_max_downl);
  $('#ulLimit').parent().children('label').children('h5').text(theUILang.Global_max_upl);

  $('#summaryAllCard .summary-label').text(theUILang.All);
  $('#summaryDownloadingCard .summary-label').text('Incomplete');
  $('#summaryCompletedCard .summary-label').text(theUILang.Finished);
  $('#summaryActiveCard .summary-label').text(theUILang.Active);
  $('#torrentSearch').attr('placeholder', (theUILang.Search || 'Search') + ' torrents, labels, or tracker errors');
  $('#toggleChromeText').text(plugin.chromeExpanded ? 'Collapse' : 'Expand');
  $('#torrentFile').text(theUILang.Torrent_file + ':');
  $('#torrentFileBrowseText').text(
    typeof theUILang.Open !== 'undefined' && theUILang.Open ? theUILang.Open : 'Choose file'
  );
  $('#createPathLabel').text((theUILang.SelectSource || 'Source path') + ' *');
  $('#createTrackersLabel').text(theUILang.Trackers || 'Trackers');
  $('#createPieceSizeLabel').text(theUILang.PieceSize || 'Piece size');
  $('#createCommentLabel').text(theUILang.Comment || 'Comment');
  $('#createSourceLabel').text(theUILang.source || 'Source');
  $('#createPrivateLabel').contents().last()[0].textContent = ' ' + (theUILang.PrivateTorrent || 'Private torrent');
  $('#createStartSeedingLabel').contents().last()[0].textContent = ' ' + (theUILang.StartSeeding || 'Start seeding after create');
  $('#createHybridLabel').contents().last()[0].textContent = ' ' + (theUILang.HybridTorrent || 'Hybrid torrent');
  plugin.updateThemeToggleUi();
  $('#addUrl').text(theUILang.add_url);

  $('#deleteOk').text(theUILang.ok);
  $('#deleteCancel').text(theUILang.Cancel);
  
  $('#sortAsc').append(' ' + theUILang.acs);
  $('#sortDesc').append(' ' + theUILang.decs);
  $('#sortOption').parent().children('label').children('h5').text(theUILang.SortTorrents);
  $('#sortOk').text(theUILang.ok);
  $('#sortCancel').text(theUILang.Cancel);
  
  $('#peersTable th').each(function(n, v) {
    $(v).text(theUILang[peersIdToLangId[v.id]]);
  });
};

mobile = plugin;
plugin.disableOthers();

$(function () {
  if (plugin.disabled) {
    return;
  }
  var href = window.location.href;
  var wantMobile =
    href.indexOf("mobile=1") >= 0 || href.indexOf("mobile%3D1") >= 0;
  if (!wantMobile) {
    return;
  }
  var attempts = 0;
  function maybeBootMobile() {
    if ($("#mainNavbar").length || plugin.disabled) {
      return;
    }
    if (theWebUI && theWebUI.settings) {
      plugin.init();
      return;
    }
    if (++attempts < 80) {
      setTimeout(maybeBootMobile, 100);
    }
  }
  setTimeout(maybeBootMobile, 0);
});
