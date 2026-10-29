from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from psycopg import AsyncConnection
from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool

from .config import get_settings

_pool: AsyncConnectionPool | None = None


async def open_pool() -> None:
    global _pool
    url = get_settings().database_url
    if not url:
        raise RuntimeError("DATABASE_URL is not set")
    _pool = AsyncConnectionPool(url, min_size=1, max_size=8, open=False,
                                kwargs={"row_factory": dict_row, "autocommit": False})
    await _pool.open()


async def ensure_pool() -> None:
    if _pool is None:
        await open_pool()


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


@asynccontextmanager
async def connection() -> AsyncIterator[AsyncConnection]:
    """A pooled connection in a transaction: commits on success, rolls back on error."""
    if _pool is None:
        raise RuntimeError("database pool is not open")
    async with _pool.connection() as conn:
        yield conn
