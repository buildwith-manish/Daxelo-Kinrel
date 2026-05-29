"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.Scopes = exports.SCOPES_KEY = void 0;
const common_1 = require("@nestjs/common");
exports.SCOPES_KEY = 'scopes';
const Scopes = (...scopes) => (0, common_1.SetMetadata)(exports.SCOPES_KEY, scopes);
exports.Scopes = Scopes;
//# sourceMappingURL=scopes.decorator.js.map