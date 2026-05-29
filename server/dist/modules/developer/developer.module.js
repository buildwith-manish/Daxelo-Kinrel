"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.DeveloperModule = void 0;
const common_1 = require("@nestjs/common");
const developer_keys_controller_1 = require("./developer-keys.controller");
const webhooks_controller_1 = require("./webhooks.controller");
const developer_service_1 = require("./developer.service");
let DeveloperModule = class DeveloperModule {
};
exports.DeveloperModule = DeveloperModule;
exports.DeveloperModule = DeveloperModule = __decorate([
    (0, common_1.Module)({
        controllers: [developer_keys_controller_1.DeveloperKeysController, webhooks_controller_1.WebhooksController],
        providers: [developer_service_1.DeveloperService],
        exports: [developer_service_1.DeveloperService],
    })
], DeveloperModule);
//# sourceMappingURL=developer.module.js.map