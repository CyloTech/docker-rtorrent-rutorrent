/*
 * Appbox skin for ruTorrent.
 */

plugin.AppboxThemeStorageKey = "appbox-rutorrent-theme-mode";

plugin.AppboxDialogIconRules = [
	{ icon: "create", pattern: /(^|\s)tcreate|create.*torrent|new.*torrent|make.*torrent/ },
	{ icon: "add", pattern: /add.*torrent|upload|magnet/ },
	{ icon: "rss", pattern: /rss|feed/ },
	{ icon: "autodl", pattern: /autodl|irc|filter/ },
	{ icon: "settings", pattern: /setting|preference|option|config/ },
	{ icon: "plugins", pattern: /plugin/ },
	{ icon: "help", pattern: /help|about/ },
	{ icon: "search", pattern: /search|find/ },
	{ icon: "remove", pattern: /remove|delete|erase/ },
	{ icon: "folder", pattern: /file|folder|directory|browse|manager/ },
	{ icon: "tag", pattern: /label|tag|category/ },
	{ icon: "link", pattern: /tracker|peer|announce|url|link/ },
	{ icon: "terminal", pattern: /log|console|task|debug/ },
	{ icon: "user", pattern: /user|password|account|auth/ },
	{ icon: "log-out", pattern: /logoff|logout|sign.*out/ },
	{ icon: "info", pattern: /info|message|confirm|warning|error|properties|details/ }
];

plugin.AppboxLogoSvg =
	"<svg class=\"appbox-brand-mark\" viewBox=\"0 0 73 77\" xmlns=\"http://www.w3.org/2000/svg\" aria-hidden=\"true\">" +
		"<g fill=\"currentColor\" fill-rule=\"evenodd\">" +
			"<path d=\"M36.4911361,0 L72.967,16.2 L73,16.185117 L73,60.7510445 L69.4960734,62.3109333 L36.50051,77 L36.5,32.465 L0,16.2345491 L36.4911361,0 Z M68.9579651,23.2178295 L42.7565455,34.8885523 L42.7565455,70.2429745 L68.9579651,58.5722517 L68.9579651,45.3143434 L64.5910618,42.8401611 L68.9579651,36.4757378 L68.9579651,23.2178295 Z\"/>" +
			"<path d=\"M13.6666667,40.1391255 L22.3333333,44.0261215 L22.3333333,39.608745 L13.6666667,35.721749 L13.6666667,40.1391255 Z M31,70 L22.3333333,66.113004 L22.3333333,52.8608745 L13.6666667,48.9738785 L13.6666667,62.2260079 L5,58.3390119 L5,23 L31,34.6609881 L31,70 Z\"/>" +
			"<polygon points=\"61 49 52 52.7453233 52 57 61 53.2546767\"/>" +
			"<polygon points=\"61 36 52 39.7453233 52 44 61 40.2546767\"/>" +
		"</g>" +
	"</svg>";

plugin.AppboxPanelIconRules = [
	{ icon: "menu", pattern: /pview|views?/ },
	{ icon: "activity", pattern: /pstate|state|status/ },
	{ icon: "tag", pattern: /plabel|labels?/ },
	{ icon: "search", pattern: /psearch|search/ },
	{ icon: "rss", pattern: /pfeed|feeds?|rss/ },
	{ icon: "link", pattern: /ptracker|trackers?/ }
];

plugin.AppboxPanelIconStyle =
	".appbox-panel-heading-icon {" +
		"background: currentColor;" +
		"display: inline-block;" +
		"flex: 0 0 auto;" +
		"height: 1rem;" +
		"margin: 0 0.625rem 0 0.2rem;" +
		"mask: var(--appbox-panel-icon, var(--icon-menu)) center / contain no-repeat;" +
		"opacity: 0.82;" +
		"width: 1rem;" +
		"-webkit-mask: var(--appbox-panel-icon, var(--icon-menu)) center / contain no-repeat;" +
	"}" +
	"div[part='heading']:hover .appbox-panel-heading-icon {" +
		"opacity: 1;" +
	"}";

plugin.AppboxPanelIconForTitle = function(title)
{
	var text = $.trim(title || "").toLowerCase();
	for(var i = 0; i < plugin.AppboxPanelIconRules.length; i++)
	{
		if(plugin.AppboxPanelIconRules[i].pattern.test(text))
		{
			return plugin.AppboxPanelIconRules[i].icon;
		}
	}
	return "menu";
}

plugin.AppboxPanelIconForPanel = function(panel)
{
	var id = (panel.getAttribute("id") || "").toLowerCase();
	var label = (panel.getAttribute("uilangtext") || panel.textContent || "").toLowerCase();
	return plugin.AppboxPanelIconForTitle(id + " " + label);
}

plugin.AppboxGetStoredTheme = function()
{
	var stored = null;
	try
	{
		stored = localStorage.getItem(plugin.AppboxThemeStorageKey);
	}
	catch(e) {}
	if((stored !== "dark") && (stored !== "light"))
	{
		stored = (window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches) ? "light" : "dark";
	}
	return stored;
}

plugin.AppboxApplyTheme = function(mode)
{
	var theme = (mode === "light") ? "light" : "dark";
	document.documentElement.setAttribute("data-appbox-theme", theme);
	try
	{
		localStorage.setItem(plugin.AppboxThemeStorageKey, theme);
	}
	catch(e) {}
	plugin.AppboxUpdateThemeToggle();
}

plugin.AppboxUpdateThemeToggle = function()
{
	var isLight = document.documentElement.getAttribute("data-appbox-theme") === "light";
	var button = $("#appboxThemeToggle");
	if(button.length)
	{
		button
			.attr("aria-pressed", isLight ? "true" : "false")
			.attr("title", isLight ? "Switch to dark mode" : "Switch to light mode");
		button.find(".appbox-theme-toggle-label").text(isLight ? "Dark" : "Light");
	}
}

plugin.AppboxToggleTheme = function()
{
	plugin.AppboxApplyTheme(document.documentElement.getAttribute("data-appbox-theme") === "light" ? "dark" : "light");
}

plugin.AppboxDialogIconForHeader = function(header)
{
	var title = header.children("div[id$='-header']").first();
	var id = (title.attr("id") || header.attr("id") || "").toLowerCase();
	var text = $.trim(title.text() || header.text() || "").toLowerCase();
	var haystack = id + " " + text;
	for(var i = 0; i < plugin.AppboxDialogIconRules.length; i++)
	{
		if(plugin.AppboxDialogIconRules[i].pattern.test(haystack))
		{
			return plugin.AppboxDialogIconRules[i].icon;
		}
	}
	return "settings";
}

plugin.AppboxUpdateDialogHeaderIcons = function(scope)
{
	var root = scope ? $(scope) : $(document);
	var headers = root.is("div.dlg-header") ? root : root.find("div.dlg-header");
	headers.each(function()
	{
		var header = $(this);
		header.attr("data-appbox-dialog-icon", plugin.AppboxDialogIconForHeader(header));
	});
}

plugin.AppboxEnhanceAutodlTabs = function(scope)
{
	var root = scope ? $(scope) : $(document);
	var tabs = root.find("#autodl-filters-tabs a, #autodl-prefs-tabs a");
	if(root.is && root.is("#autodl-filters-tabs a, #autodl-prefs-tabs a"))
	{
		tabs = tabs.add(root);
	}
	tabs
		.attr("role", "button")
		.attr("tabindex", "0")
		.off("keydown.appboxAutodlTabs")
		.on("keydown.appboxAutodlTabs", function(e)
		{
			if((e.key === " ") || (e.key === "Spacebar"))
			{
				e.preventDefault();
				$(this).trigger("click");
			}
		});
}

plugin.AppboxUpdateCategoryPanelIcons = function(scope)
{
	var root = scope ? $(scope) : $(document);
	var panels = root.find("category-panel");
	if(root.is && root.is("category-panel"))
	{
		panels = panels.add(root);
	}

	panels.each(function()
	{
		var panel = this;
		panel.setAttribute("data-appbox-panel-icon", plugin.AppboxPanelIconForPanel(panel));
		if(!panel.shadowRoot)
		{
			return;
		}

		var heading = panel.shadowRoot.querySelector("div[part='heading']");
		if(!heading)
		{
			return;
		}

		if(!panel.shadowRoot.querySelector("#appboxPanelIconStyle"))
		{
			var style = document.createElement("style");
			style.id = "appboxPanelIconStyle";
			style.textContent = plugin.AppboxPanelIconStyle;
			panel.shadowRoot.appendChild(style);
		}

		var icon = heading.querySelector(".appbox-panel-heading-icon");
		if(!icon)
		{
			icon = document.createElement("span");
			icon.className = "appbox-panel-heading-icon";
			icon.setAttribute("aria-hidden", "true");
			heading.insertBefore(icon, heading.firstChild);
		}

		panel.setAttribute("data-appbox-panel-icon", plugin.AppboxPanelIconForTitle(panel.getAttribute("data-appbox-panel-icon") + " " + heading.textContent));
	});
}

plugin.AppboxUpdateDialogState = function()
{
	var hasDialog = $("div.dlg-window:visible").length > 0;
	$("html").toggleClass("appbox-dialog-open", hasDialog);
}

plugin.AppboxInstallDialogIconObserver = function()
{
	plugin.AppboxUpdateDialogHeaderIcons(document);
	plugin.AppboxEnhanceAutodlTabs(document);
	plugin.AppboxUpdateCategoryPanelIcons(document);
	plugin.AppboxUpdateDialogState();
	if(!window.MutationObserver || plugin.AppboxDialogIconObserver)
	{
		return;
	}
	var target = document.getElementById("dialog-container") || document.body;
	plugin.AppboxDialogIconObserver = new MutationObserver(function(mutations)
	{
		for(var i = 0; i < mutations.length; i++)
		{
			for(var j = 0; j < mutations[i].addedNodes.length; j++)
			{
				var node = mutations[i].addedNodes[j];
				if(node.nodeType === 1)
				{
					plugin.AppboxUpdateDialogHeaderIcons(node);
					plugin.AppboxEnhanceAutodlTabs(node);
					plugin.AppboxUpdateCategoryPanelIcons(node);
				}
			}
		}
		plugin.AppboxUpdateCategoryPanelIcons(document);
		plugin.AppboxUpdateDialogState();
	});
	plugin.AppboxDialogIconObserver.observe(target, { childList: true, subtree: true, attributes: true, attributeFilter: ["class", "style"] });
}

plugin.AppboxInstallChrome = function()
{
	var bar = $("#t .container-fluid").first();
	if(!bar.length || $("#appboxBrand").length)
	{
		return;
	}

	bar.prepend(
		"<a id=\"appboxBrand\" href=\"https://www.appbox.co/dashboard\" target=\"_blank\" rel=\"noopener noreferrer\" title=\"Appbox Dashboard\">" +
			plugin.AppboxLogoSvg +
		"</a>"
	);

	bar.append(
		"<button id=\"appboxThemeToggle\" type=\"button\" aria-pressed=\"false\" title=\"Switch theme\">" +
			"<span class=\"appbox-theme-toggle-icon\" aria-hidden=\"true\"></span>" +
			"<span class=\"appbox-theme-toggle-label\">Light</span>" +
		"</button>"
	);

	$("#appboxThemeToggle").on("click", function(e)
	{
		e.preventDefault();
		plugin.AppboxToggleTheme();
	});

	$("#mnu_go")
		.attr("title", "Run search")
		.attr("aria-label", "Run search");

	$("#query")
		.off("input.appboxSearchState keyup.appboxSearchState change.appboxSearchState")
		.on("input.appboxSearchState keyup.appboxSearchState change.appboxSearchState", plugin.AppboxUpdateSearchState);

	plugin.AppboxUpdateThemeToggle();
	plugin.AppboxUpdateSearchState();
}

plugin.AppboxUpdateSearchState = function()
{
	var value = $.trim($("#query").val() || "");
	$("#rc").toggleClass("appbox-search-active", value.length > 0);
}

plugin.AppboxApplyTheme(plugin.AppboxGetStoredTheme());

plugin.AppboxAllDone = plugin.allDone;
plugin.allDone = function()
{
	plugin.AppboxAllDone.call(this);
	plugin.AppboxInstallChrome();
	plugin.AppboxInstallDialogIconObserver();
	$.each(["diskapceh", "diskspace", "quotaspace", "cpuload"], function(ndx, name)
	{
		var plg = thePlugins.get(name);
		if(plg && plg.enabled)
		{
			plg.prgStartColor = new RGBackground("#10B981");
			plg.prgEndColor = new RGBackground("#EF4444");
		}
	});
}

plugin.oldTableCreate = dxSTable.prototype.create;
dxSTable.prototype.create = function(ele, styles, aName)
{
	plugin.oldTableCreate.call(this, ele, styles, aName);
	this.prgStartColor = new RGBackground("#EF4444");
	this.prgEndColor = new RGBackground("#10B981");
}
