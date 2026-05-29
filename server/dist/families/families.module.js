"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.FamiliesModule = void 0;
const common_1 = require("@nestjs/common");
const families_controller_1 = require("./families.controller");
const families_service_1 = require("./families.service");
let FamiliesModule = class FamiliesModule {
};
exports.FamiliesModule = FamiliesModule;
exports.FamiliesModule = FamiliesModule = __decorate([
    (0, common_1.Module)({
        controllers: [families_controller_1.FamiliesController],
        providers: [families_service_1.FamiliesService],
        exports: [families_service_1.FamiliesService],
    })
], FamiliesModule);
//# sourceMappingURL=families.module.js.map