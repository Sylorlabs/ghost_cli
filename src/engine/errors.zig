pub const CliError = error{
    EngineNotFound,
    EngineBinaryNotFound,
    EngineExecutionFailed,
    InvalidJsonContract,
    MissingRequiredField,
    UnsupportedCommand,
    UnknownReasoningLevel,
};
