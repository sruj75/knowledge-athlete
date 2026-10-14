"""Provider usage with disjoint input, cache, output and reasoning buckets."""

from pydantic import BaseModel, Field


class GeminiUsage(BaseModel):
    promptTokenCount: int = Field(default=0, ge=0)
    cachedContentTokenCount: int = Field(default=0, ge=0)
    candidatesTokenCount: int = Field(default=0, ge=0)
    thoughtsTokenCount: int = Field(default=0, ge=0)
    totalTokenCount: int | None = Field(default=None, ge=0)

    def wire(self) -> dict[str, int]:
        result = {
            'input_tokens': max(0, self.promptTokenCount - self.cachedContentTokenCount),
            'cached_input_tokens': self.cachedContentTokenCount,
            'output_tokens': self.candidatesTokenCount,
            'thinking_tokens': self.thoughtsTokenCount,
        }
        if self.totalTokenCount is not None:
            result['total_tokens'] = self.totalTokenCount
        return result

    def langfuse(self) -> dict[str, int]:
        return {
            'input': max(0, self.promptTokenCount - self.cachedContentTokenCount),
            'cache_read_input_tokens': self.cachedContentTokenCount,
            'output': self.candidatesTokenCount,
            'reasoning_output_tokens': self.thoughtsTokenCount,
        }
