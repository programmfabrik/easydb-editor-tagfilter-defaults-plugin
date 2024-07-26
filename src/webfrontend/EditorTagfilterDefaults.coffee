###
 * easydb-editor-tagfilter-defaults
 * Copyright (c) 2013 - 2016 Programmfabrik GmbH
 * MIT Licence
 * https://github.com/programmfabrik/coffeescript-ui, http://www.coffeescript-ui.org
###

class EditorTagfilterDefaults extends CUI.Element
	readOpts: ->
		super()
		BaseConfig.registerPlugin(new BaseConfigEditorTagfilterDefaults())

		filters_by_mask_name = {}
		baseConfig = ez5.session.getBaseConfig("plugin", "easydb-editor-tagfilter-defaults-plugin")
		baseConfig = baseConfig.system or baseConfig # TODO: Remove this after #64076 is merged.
		filters = baseConfig["editor-tagfilter-defaults"]?.filters or []

		if not filters
			return

		for filter in filters
			mask_name = ez5.mask.CURRENT._mask_by_id[filter.mask_id]?.name

			if not mask_name
				console.warn("EditorTagfilterDefaults: Unable to load mask", filter)
				continue

			if not filter.default or filter.operation.length == 0
				continue

			if not filters_by_mask_name[mask_name]
				filters_by_mask_name[mask_name] = []

			filters_by_mask_name[mask_name].push(filter)

			if filter.tagfilter
				if CUI.util.isString(filter.tagfilter)
					filter.tagfilter = JSON.parse(filter.tagfilter)
			else
				filter.tagfilter = null

			if filter.pool_id
				if CUI.util.isString(filter.pool_id)
					filter.pool_id = JSON.parse(filter.pool_id)
			else
				filter.pool_id = {ids:[]}

			filter.default = JSON.parse(filter.default)


		# console.error "filters by mask name", filters_by_mask_name

		CUI.Events.listen
			type: [
				"editor-load"
				"editor-tags-field-changed"
				"pool-field-changed"
			]

			call: (ev, info) =>

				if not info.editor_data
					return

				applyFilters =  filters_by_mask_name[ info.editor_data.mask_name ]
				# console.error "add new result object", ev, info, info.editor_data.mask_name, apply_filters

				if not applyFilters
					return

				object = info.object or info.new_object
				if not object
					return

				switch info.editor.getMode()
					when "bulk"
						# not applying filters in bulk more
						return
					when "new"
						operation = "insert"
					when "single"
						operation = "update"
						if ev.getType() == "editor-load"
							# only execute when in "new" mode
							return

				applyFilters = applyFilters.filter((applyFilter) ->
					operation in applyFilter.operation and applyFilter.default?.length > 0
				)

				objectPool = info.new_pool or info.editor_data?._pool;

				if applyFilters.length > 0
					@applyFilters(object, objectPool, applyFilters)
					info.editor?.reloadEditor()
				return

	# filter =
	#  default: [preset_object]
	#  mask_id: Number
	#  operation: [String]
	#  tagfilter:
	#    tagfilter: {all: {..}, ..}
	applyFilters: (object, objectPool, applyFilters) ->
		fields = object.mask.getFields("all")
		filtersByField = {}

		find_field = (column_id) =>
			for field in fields
				if field instanceof MaskSplitter
					continue

				if field.id() == column_id
					return field

			return

		for applyFilter in applyFilters
			tagfilter_ok = TagFilter.matchesTags(applyFilter.tagfilter.tagfilter, object.getData()._tags)

			#If we have pools set in the filter and the object has a pool set:
			if applyFilter.pool_id.ids.length > 0 and objectPool
				matchPool = false
				for filterPoolId in applyFilter.pool_id.ids
					if parseInt(filterPoolId) == objectPool.pool._id
						matchPool = true
						break
				if not matchPool
					continue

			for rule, idx in applyFilter.default
				rule._idx = idx
				rule._tagfilter_match = tagfilter_ok
				switch rule.action
					when "preset"
						field = find_field(rule.column_id)
						if not field
							console.error("EditorTagfilterDefaults: Skipping unknown field: " + rule.column_id)
							continue

						if not filtersByField[field.id()]
							filtersByField[field.id()] =
								field: field
								rules: []
						filtersByField[field.id()].rules.push(rule)
					else
						console.error("EditorTagfilterDefaults: Skipping unknown action: "+rule.action)

		for _, filterByField of filtersByField
			matchRules = filterByField.rules.filter((rule) -> rule._tagfilter_match)
			unmatchedRules = filterByField.rules.filter((rule) -> not rule._tagfilter_match)

			if unmatchedRules.length == filterByField.rules.length
				for rule in unmatchedRules
					if filterByField.field instanceof DateColumn and rule.modifier
						rule = @replaceDateRule(rule, filterByField.field)
					filterByField.field.emptyEditorInputValue(rule.value, object.getData())
				continue

			for rule in matchRules
				if filterByField.field instanceof DateColumn and rule.modifier
					rule = @replaceDateRule(rule, filterByField.field)
				filterByField.field.updateEditorInputValue(rule.value, object.getData())

		return

	replaceDateRule: (rule, field) ->
		if "today" in rule.modifier
			if field instanceof DateTimeColumn
				rule.value = CUI.DateTime.format((new Date()).toISOString(), "display_short")
			else
				rule.value = CUI.DateTime.format((new Date()).toISOString().substr(0,10), "display_short")
		return rule

class BaseConfigEditorTagfilterDefaults extends BaseConfigPlugin

	getFieldDefFromParm: (baseConfig, pname, def) ->

		toggleUpdateOperation = (data, form) ->
			parentForm = form.getForm() or form
			fieldData = data["tagfilter"]["tagfilter"]
			tagFilterField = parentForm.getFieldsByName("tagfilter")[0]
			operationField = parentForm.getFieldsByName("operation")[0]
			nPoolIds = data?.pool_id?.ids?.length or 0
			if nPoolIds > 0
				operationField.enableOption("update")
			else if CUI.util.isEmpty(fieldData) or tagFilterField.isDisabled()
				operationField.disableOption("update")
			else
				operationField.enableOption("update")

		getPresetOptions = (mask_id) ->
			validField = (field) ->
				if field instanceof TextColumn
					return true
				if field instanceof DateColumn and field not instanceof DateRangeColumn
					return true
				if field instanceof BooleanColumn
					return true
				return false

			mask = ez5.mask.CURRENT._mask_instance_by_name[ez5.mask.CURRENT._mask_by_id[mask_id].name]
			options = []
			for field in mask.getFields("editor")
				if validField(field)
					options.push
						text: field.nameLocalized()
						value: field.id()
						_field: field
			return options

		switch def.plugin_type
			when "mask-select"
				# sort all masks by objecttype and mask
				mask_ids = []
				get_ot_name = (mask_id) ->
					ez5.schema.CURRENT._table_by_id[ez5.mask.CURRENT._mask_by_id[mask_id].table_id]._name_localized

				get_mask_name = (mask_id) ->
					ez5.mask.CURRENT._mask_by_id[mask_id]._name_localized

				mask_ids = (mask.mask_id for mask in ez5.mask.CURRENT.masks)

				mask_ids.sort (a, b) ->

					a_ot_name = get_ot_name(a)
					b_ot_name = get_ot_name(b)

					if a_ot_name == b_ot_name
						a_mask_name = get_mask_name(a)
						b_mask_name = get_mask_name(b)
						return CUI.util.compareIndex(a_mask_name.toLocaleLowerCase(), b_mask_name.toLocaleLowerCase())

					return CUI.util.compareIndex(a_ot_name.toLocaleLowerCase(), b_ot_name.toLocaleLowerCase())

				mask_opts = []
				last_ot_name = null

				for idMask in mask_ids
					options = getPresetOptions(idMask)
					if options.length == 0
						continue

					ot_name = get_ot_name(idMask)
					mask_name = get_mask_name(idMask)

					if last_ot_name != ot_name
						mask_opts.push
							label: ot_name
						last_ot_name = ot_name

					mask_opts.push
						text: mask_name
						text_selected: ot_name+": "+mask_name
						value: idMask

				toggleTagFilter = (select, data) =>
					idMask = data[pname]
					mask = ez5.mask.CURRENT._mask_by_id[idMask]
					if not mask
						return

					form = select.getForm().getForm() # Parent form.
					tagfilter = form.getFieldsByName("tagfilter")[0]
					hasTags = ez5.schema.CURRENT._table_by_id[mask.table_id]?.has_tags
					if hasTags
						tagfilter.enable()
					else
						tagfilter.disable()

				field =
					type: CUI.Form
					onRender: (form) =>
						toggleUpdateOperation(form.getData(), form)
					fields: [
						type: CUI.Select
						options: mask_opts
						name: pname
						onDataInit: (select, data) =>
							toggleTagFilter(select, data)
						onDataChanged: (_, select) ->
							toggleTagFilter(select, select.getData())
							toggleUpdateOperation(select.getData(), select.getForm())
					,
						type: CUI.FormButton
						appearance: "flat"
						icon: ez5.loca.get_key("editor.tagfilter.defaults.replacement.button|icon")
						text: ez5.loca.get_key("editor.tagfilter.defaults.replacement.button|text")
						tooltip:
							text: ez5.loca.get_key("editor.tagfilter.defaults.replacement.button|tooltip")
						onClick: (ev, button) =>
							mask = ez5.mask.CURRENT._mask_by_id[button.getData()[pname]]
							if not mask
								return

							mask_inst = ez5.mask.CURRENT._mask_instance_by_name[mask.name]
							ro = new ResultObjectDemo(mask: mask_inst, format: "long", format_linked_object: "standard")
							rec = mask_inst.getReplacementRecord(ro.getData())
							repl =  []
							for key of rec
								repl.push("%"+key+"%")
							# console.error "formButton", data, mask_inst, ro, rec, repl

							if ez5.session.getReplacementRecord?()
								# We get replacement for session data.
								for key of ez5.session.getReplacementRecord()
									repl.push("%"+key+"%")

							new CUI.Tooltip
								on_click: true
								element: button
								class: "ez5-editor-tagfilter-defaults-replacements-help"
								text: repl.join("\n")
							.show()
					]

			when "column-default-value"

				field =
					type: CUI.DataTable
					maximize_horizontal: true
					name: pname
					onDataInit: (_, data) =>
						if not data[pname] or not CUI.util.isArray(data[pname])
							data[pname] = []
					fields: [
						form:
							label: $$(baseConfig.locaKey("parameter")+".type.label")
						type: CUI.Select
						name: "action"
						options: [
							text: $$(baseConfig.locaKey("option")+".type.preset")
							value: "preset"
						]
					,
						form:
							label: $$(baseConfig.locaKey("parameter")+".column_id.label")
						type: CUI.Select
						name: "column_id"
						onDataChanged: (_, selectField) =>
							selectField.getForm().getFieldsByName("data-field-proxy")[0].reload()
						options: (df) =>
							mask_id = df.getForm().getDataTable().getData().mask_id
							CUI.util.assert(mask_id > 0, "EditorTagfilterDefaults.column-default-value", "Unable to get mask_id from data table data.", dataField: df)
							if ez5.mask.CURRENT._mask_by_id[mask_id]
								return getPresetOptions(mask_id)
							else
								return []

					,
						type: CUI.DataFieldProxy
						call_others: false
						form:
							label: $$(baseConfig.locaKey("parameter")+".value.label")
						name: "data-field-proxy"
						element: (dataField) =>
							selectOptions = dataField.getForm().getFieldsByName("column_id")[0]?.getOptions()
							data = dataField.getData()

							findField = =>
								for option in selectOptions
									if option.value == data.column_id
										return option._field

							dataField = findField()

							if dataField instanceof LocaTextColumn
								if not CUI.isPlainObject(data.value)
									data.value = {}

								multiInput = new CUI.MultiInput
									textarea: (dataField instanceof LocaTextMultiColumn)
									data: data
									name: "value"
									control: ez5.loca.getLanguageControlAdmin()
								return multiInput.start()
							else if dataField instanceof NumberColumn
								if not CUI.util.isNumber(data.value)
									delete data.value

								numberInput = new CUI.NumberInput
									data: data
									name: "value"
								return numberInput.start()
							else if dataField instanceof DateColumn
								dateTime = dataField instanceof DateTimeColumn
								proxyInput = new CUI.DataFieldProxy
									element: (dataField) =>
										options = new CUI.Options
											name: "modifier"
											data: data
											options: [
												text: $$(baseConfig.locaKey("parameter")+".date.replacement.today|text")
												value: "today"
												tooltip: text: $$(baseConfig.locaKey("parameter")+".date.replacement.today|tooltip")
											]
											onDataChanged: =>
												dataField.reload()
										if "today" in data.modifier
											dateInput = null
										else
											dateInput = new CUI.DateTime
												name: "value"
												data: data
												input_types: if dateTime then ["date_time"] else ["date"]
										hl = new CUI.HorizontalList
											maximize_horizontal: true
											content: [
												options,
												dateInput
											]
										return hl
								return proxyInput.start()
							else if dataField instanceof BooleanColumn
								if not CUI.util.isBoolean(data.value)
									data.value = true

								checkbox = new CUI.Checkbox
									data: data
									name: "value"
								return checkbox.start()

							else
								if CUI.isPlainObject(data.value)
									data.value = ""

								numberInput = new CUI.Input
									textarea: (dataField instanceof TextMultiColumn)
									data: data
									name: "value"
								return numberInput.start()
					]

			when "tag-filter"

				tagFilter = new TagFilter
					tagForm: ez5.tagForm
					name: pname

				field = tagFilter.getField
					onDataChanged: (data, dataField) =>
						tagFilterData =
							tagfilter : data
						toggleUpdateOperation(tagFilterData, dataField.getForm())
				field.name = pname

			when "pool-select"

				field =
					type: CUI.DataFieldProxy
					call_others: false
					name: pname
					element: (dataField) =>

						getPoolBtnText = (data) ->
							if data?.ids?.length > 0
								return $$("admin.message.pools.button.selected", count: data.ids.length)
							else
								return $$("admin.message.pools.button")

						formButton = new CUI.FormButton
							text: getPoolBtnText(dataField.getData().pool_id)
							active: dataField.getData().pool_id?.ids?.length > 0
							onClick: () =>
								poolData = () => dataField.getData();
								temporalData = CUI.util.copyObject(poolData().pool_id,true) or {}
								@__pools_form = new PoolsForm
									data: temporalData
									treeOpts:
										class: 'cui-lv--has-datafields'
										maximize: false
										rowMove: false
										cols: ["auto"]

								doneButton = new CUI.Button
									text: $$("base.done")
									primary: true
									onClick: (ev) =>
										poolData().pool_id = @__pools_form.getSaveData()
										poolFormModal.destroy()
										formButton.setText(getPoolBtnText(dataField.getData().pool_id))
										if dataField.getData().pool_id?.ids?.length > 0
											formButton.activate()
										else
											formButton.deactivate()
										CUI.Events.trigger
											node: formButton
											type: "data-changed"
										toggleUpdateOperation(dataField.getData(), dataField.getForm())

								cancelButton = new CUI.Button
									text: $$("base.abort")
									onClick: (ev) =>
										poolFormModal.destroy()

								poolFormModal = new CUI.Modal
									class: "cui-pools-form"
									cancel: true
									pane:
										header_left: new CUI.Label
											text: $$("admin.message.pools.pools_form.title")
										content: @__pools_form.renderForm()
										footer_right: [cancelButton, doneButton]
									onDestroy: =>
										onClose?()
										return
								poolFormModal.show()

						formButton.start()

		return field


ez5.defaults_done ->
	new EditorTagfilterDefaults()
