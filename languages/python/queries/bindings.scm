(def_statement) @scope.function
(async_def_statement) @scope.function
(class_statement) @scope.class
(def_statement (identifier) @definition.function)
(async_def_statement (identifier) @definition.function)
(class_statement (identifier) @definition.type)
(parameter_item (identifier) @definition.parameter)
(identifier) @reference.variable
