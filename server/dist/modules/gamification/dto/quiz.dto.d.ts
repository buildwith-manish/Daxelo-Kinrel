export declare class CreateQuizDto {
    category?: string;
    language: string;
    count: number;
    difficulty?: string;
}
export declare class SubmitQuizDto {
    answers: number[];
}
