#!/usr/bin/env python3
"""Benchmark LM Studio local API models.

Features:
1. Auto-detect loaded models via /v1/models.
2. Skip embedding-only models (heuristic name match).
3. For each chat-capable model:
   - Generate N random Chinese questions (default 100).
   - Send each as a streamed chat completion.
   - Record: prompt, time_to_first_token(s), completion_time(s), completion_tokens,
             total_tokens, tokens_per_second, finish_reason (EOS / other).
4. Aggregate per-model averages and write both CSV and JSON summary.

Usage:
    python utils/benchmark_lmstudio.py \
        --host http://localhost:1234 \
        --questions 100 \
        --max-tokens 512 \
        --out-prefix utils/lmstudio_benchmark

Dependencies:
    pip install requests tiktoken (tiktoken optional; fallback simple tokenizer)

Notes:
    - LM Studio provides an OpenAI-compatible API. This script assumes
      /v1/models and /v1/chat/completions endpoints are available.
    - Streaming is used to measure time to first token precisely.
    - Stop reason "EOS" is mapped from finish_reason == 'stop'.
"""

import argparse
import csv
import json
import random
import re
import sys
import time
from dataclasses import dataclass, asdict
from typing import List, Dict, Any, Optional

import requests

try:
    import tiktoken  # type: ignore
    _HAS_TIKTOKEN = True
except Exception:  # pragma: no cover
    _HAS_TIKTOKEN = False


QUESTION_TEMPLATES = [
    "请简要解释{topic}的核心概念是什么？",
    "{topic}在实际应用中常见的性能瓶颈有哪些？",
    "给出一个改进{topic}效率的思路。",
    "{topic}涉及哪些关键算法或数据结构？",
    "如果需要在生产环境优化{topic}，应优先考虑哪些指标？",
    "{topic}与其他相关技术相比的优势是什么？",
    "构建一个支持高并发的{topic}系统需要注意哪些因素？",
    "{topic}未来的发展趋势可能是什么？",
    "请用示例说明{topic}的一个典型使用场景。",
    "在安全角度审视{topic}，最重要的风险点有哪些？",
]

TOPICS = [
    "向量检索", "知识库构建", "多轮对话管理", "模型蒸馏", "Prompt工程", "检索增强生成",
    "大语言模型微调", "参数高效微调", "数据清洗", "实体识别", "关系抽取", "语义匹配",
    "文本分类", "文本摘要", "对话意图识别", "长文本处理", "上下文窗口扩展", "函数调用",
    "流式输出", "推理加速", "量化", "剪枝", "嵌入向量质量", "召回率评估", "重排序",
    "知识图谱", "医学问答", "电子病历结构化", "风险预测", "模型对齐", "幻觉检测", "RAG评估",
    "可解释性", "日志监控", "Prompt模板版本管理", "模型选择策略", "自动化评测", "模型集成",
    "多模型路由", "扩展性设计", "缓存策略", "查询分析", "并发控制", "速率限制", "失败重试",
    "负载均衡", "服务治理", "观测性", "成本优化", "容灾切换", "数据脱敏",
]


@dataclass
class QuestionResult:
    model: str
    index: int
    prompt: str
    time_to_first_token: float
    completion_time: float
    completion_tokens: int
    prompt_tokens: int
    total_tokens: int
    tokens_per_second: float
    finish_reason: str


def approximate_token_count(text: str) -> int:
    """Fallback token count approximation when usage metrics missing."""
    if _HAS_TIKTOKEN:
        try:
            enc = tiktoken.get_encoding("cl100k_base")
            return len(enc.encode(text))
        except Exception:
            pass
    tokens = re.findall(r"\w+|[。，；；,.!?！？]", text)
    return len(tokens)


def fetch_models(host: str) -> List[str]:
    url = host.rstrip("/") + "/v1/models"
    print(f"[DEBUG] 正在从 {url} 获取模型列表...")
    try:
        resp = requests.get(url, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        models_field = data.get("data") or []
        models = []
        for m in models_field:
            mid = m.get("id") or m.get("name")
            if mid:
                models.append(mid)
        print(f"[DEBUG] 发现 {len(models)} 个模型: {', '.join(models[:3])}{'...' if len(models) > 3 else ''}")
        return models
    except Exception as e:
        print(f"[ERROR] 获取模型列表失败: {e}")
        return []


def is_embedding_model(model_id: str) -> bool:
    lower = model_id.lower()
    return any(k in lower for k in ["embedding", "bge", "text-embedding", "embed"])


def generate_questions(n: int, seed: Optional[int] = None) -> List[str]:
    if seed is not None:
        random.seed(seed)
    questions = []
    for i in range(n):
        topic = random.choice(TOPICS)
        template = random.choice(QUESTION_TEMPLATES)
        questions.append(template.format(topic=topic))
    return questions


def stream_chat_completion(host: str, model: str, prompt: str, max_tokens: int, temperature: float, verbose: bool = False, stream_timeout: int = 60) -> Dict[str, Any]:
    url = host.rstrip("/") + "/v1/chat/completions"
    headers = {"Content-Type": "application/json"}
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": temperature,
        "stream": True,
    }
    start_time = time.time()
    first_token_time: Optional[float] = None
    collected_text_parts: List[str] = []
    finish_reason = "unknown"
    usage: Dict[str, int] = {}
    chunk_count = 0
    last_chunk_time = time.time()

    try:
        if verbose:
            print(f"[DEBUG] 发送请求到 {url}, model={model}, max_tokens={max_tokens}")
        with requests.post(url, headers=headers, json=payload, stream=True, timeout=30) as r:
            r.raise_for_status()
            for raw_line in r.iter_lines():
                # 检查是否超时（距离上次收到chunk超过stream_timeout秒）
                current_time = time.time()
                if current_time - last_chunk_time > stream_timeout:
                    raise TimeoutError(f"流式响应超时：超过{stream_timeout}秒未收到数据")
                
                if not raw_line:
                    continue
                
                last_chunk_time = current_time
                line = raw_line.decode("utf-8").strip()
                if line == "data: [DONE]":
                    break
                if line.startswith("data: "):
                    line = line[6:].strip()
                if line == "[DONE]":
                    break
                try:
                    chunk = json.loads(line)
                    chunk_count += 1
                    if verbose and chunk_count % 50 == 0:
                        print(f"[DEBUG] 已接收 {chunk_count} 个chunk...")
                except json.JSONDecodeError as jde:
                    if verbose:
                        print(f"[WARN] JSON 解析失败: {line[:100]}")
                    continue
                choices = chunk.get("choices") or []
                if choices:
                    c0 = choices[0]
                    delta = c0.get("delta") or {}
                    if delta.get("content"):
                        if first_token_time is None:
                            first_token_time = time.time()
                            if verbose:
                                print(f"[DEBUG] 首个 token 到达，耗时 {first_token_time - start_time:.3f}s")
                        collected_text_parts.append(delta["content"])
                    if c0.get("finish_reason"):
                        finish_reason = c0["finish_reason"]
                if chunk.get("usage"):
                    usage = chunk["usage"]
        if verbose:
            print(f"[DEBUG] 流式完成，共 {chunk_count} 个 chunk")
    except requests.exceptions.Timeout as te:
        return {
            "error": f"连接超时: {te}",
            "model": model,
            "prompt": prompt[:50],
        }
    except TimeoutError as te:
        return {
            "error": str(te),
            "model": model,
            "prompt": prompt[:50],
        }
    except requests.exceptions.RequestException as re:
        return {
            "error": f"请求失败: {re}",
            "model": model,
            "prompt": prompt[:50],
        }
    except Exception as e:
        return {
            "error": f"未知错误: {type(e).__name__}: {e}",
            "model": model,
            "prompt": prompt[:50],
        }

    end_time = time.time()
    full_text = "".join(collected_text_parts)
    time_to_first = (first_token_time - start_time) if first_token_time else None
    completion_time = (end_time - first_token_time) if first_token_time else (end_time - start_time)

    completion_tokens = usage.get("completion_tokens") or approximate_token_count(full_text)
    prompt_tokens = usage.get("prompt_tokens") or approximate_token_count(prompt)
    total_tokens = usage.get("total_tokens") or (completion_tokens + prompt_tokens)

    if completion_time > 0 and first_token_time:
        tokens_per_sec = completion_tokens / completion_time
    else:
        tokens_per_sec = 0.0

    mapped_finish = "EOS" if finish_reason == "stop" else finish_reason

    return {
        "model": model,
        "prompt": prompt,
        "generated_text": full_text,
        "time_to_first_token": time_to_first,
        "completion_time": completion_time,
        "completion_tokens": completion_tokens,
        "prompt_tokens": prompt_tokens,
        "total_tokens": total_tokens,
        "tokens_per_second": tokens_per_sec,
        "finish_reason": mapped_finish,
        "raw_finish_reason": finish_reason,
    }


def benchmark_model(host: str, model: str, questions: List[str], max_tokens: int, temperature: float, verbose: bool = False, retry: int = 2, delay: float = 1.0, stream_timeout: int = 60) -> Dict[str, Any]:
    print(f"\n{'='*60}")
    print(f"[INFO] 开始测试模型: {model}")
    print(f"[INFO] 问题数量: {len(questions)}, max_tokens: {max_tokens}, temperature: {temperature}")
    print(f"{'='*60}")
    results: List[QuestionResult] = []
    errors: List[Dict[str, Any]] = []
    
    for idx, q in enumerate(questions, start=1):
        attempt = 0
        success = False
        r = None
        
        while attempt <= retry and not success:
            if attempt > 0:
                print(f"  [重试 {attempt}/{retry}] 第 {idx} 题...")
                time.sleep(1)  # 短暂延迟再重试
            
            r = stream_chat_completion(host, model, q, max_tokens, temperature, verbose=(verbose and attempt == 0), stream_timeout=stream_timeout)
            
            if "error" not in r:
                success = True
            else:
                attempt += 1
        
        if not success and r:
            print(f"[ERROR] 第{idx}题失败(已重试{retry}次): {r['error']}")
            errors.append(r)
            continue
        
        if r:
            qr = QuestionResult(
                model=model,
                index=idx,
                prompt=q,
                time_to_first_token=r["time_to_first_token"] or -1.0,
                completion_time=r["completion_time"],
                completion_tokens=r["completion_tokens"],
                prompt_tokens=r["prompt_tokens"],
                total_tokens=r["total_tokens"],
                tokens_per_second=r["tokens_per_second"],
                finish_reason=r["finish_reason"],
            )
            results.append(qr)
            
            # 实时显示进度和关键指标
            print(f"  ✓ [{idx}/{len(questions)}] TTFT: {qr.time_to_first_token:.3f}s | "
                  f"完成: {qr.completion_time:.2f}s | "
                  f"Token数: {qr.completion_tokens} | "
                  f"速度: {qr.tokens_per_second:.1f} tok/s | "
                  f"结束: {qr.finish_reason}")
            
            # 请求间隔延迟，避免过快
            if idx < len(questions) and delay > 0:
                time.sleep(delay)
    def avg(field: str) -> float:
        vals = [getattr(r, field) for r in results if getattr(r, field) >= 0]
        return sum(vals) / len(vals) if vals else 0.0
    agg = {
        "model": model,
        "total_prompts": len(questions),
        "successful_prompts": len(results),
        "failed_prompts": len(errors),
        "avg_time_to_first_token": avg("time_to_first_token"),
        "avg_completion_time": avg("completion_time"),
        "avg_completion_tokens": avg("completion_tokens"),
        "avg_tokens_per_second": avg("tokens_per_second"),
        "finish_reason_counts": {},
    }
    fr_counts: Dict[str, int] = {}
    for r in results:
        fr_counts[r.finish_reason] = fr_counts.get(r.finish_reason, 0) + 1
    agg["finish_reason_counts"] = fr_counts
    return {"aggregate": agg, "details": [asdict(r) for r in results], "errors": errors}


def write_csv(path: str, per_model_data: List[Dict[str, Any]]):
    fieldnames = [
        "model", "total_prompts", "successful_prompts", "failed_prompts",
        "avg_time_to_first_token", "avg_completion_time", "avg_completion_tokens",
        "avg_tokens_per_second", "finish_reason_counts",
    ]
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for m in per_model_data:
            row = m["aggregate"].copy()
            row["finish_reason_counts"] = json.dumps(row["finish_reason_counts"], ensure_ascii=False)
            writer.writerow(row)


def main():
    parser = argparse.ArgumentParser(description="Benchmark LM Studio local models")
    parser.add_argument("--host", default="http://localhost:1234", help="LM Studio API base URL")
    parser.add_argument("--questions", type=int, default=100, help="Number of random questions per model")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for reproducibility")
    parser.add_argument("--max-tokens", type=int, default=512, help="Generation max_tokens (限制生成长度，省略则使用服务端默认值，通常不会无限生成)")
    parser.add_argument("--temperature", type=float, default=0.7, help="Sampling temperature")
    parser.add_argument("--out-prefix", default="utils/lmstudio_benchmark", help="Output file prefix (without extension)")
    parser.add_argument("--models", nargs="*", help="指定要测试的模型列表 (优先级最高，覆盖 include/exclude)")
    parser.add_argument("--include", nargs="*", help="Only benchmark specified model ids (optional)")
    parser.add_argument("--exclude", nargs="*", help="Exclude model ids (optional)")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose debug output")
    parser.add_argument("--retry", type=int, default=2, help="Number of retries on error")
    parser.add_argument("--delay", type=float, default=1.0, help="每次请求之间的延迟秒数，避免请求过快 (default: 1.0)")
    parser.add_argument("--stream-timeout", type=int, default=60, help="流式响应单次读取超时秒数 (default: 60)")
    args = parser.parse_args()

    print(f"\n{'#'*70}")
    print(f"# LM Studio 模型性能基准测试")
    print(f"# 主机: {args.host}")
    print(f"# 问题数: {args.questions}, 种子: {args.seed}")
    print(f"# Max tokens: {args.max_tokens}, 温度: {args.temperature}")
    print(f"{'#'*70}\n")

    all_models = fetch_models(args.host)
    if not all_models:
        print("[ERROR] 无可用模型，退出。")
        sys.exit(1)

    # 如果指定了 --models，直接使用该列表（不过滤 embedding，用户自己负责）
    if args.models:
        candidate_models = args.models
        print(f"[INFO] 使用 --models 指定的模型列表: {candidate_models}")
        # 验证模型是否在可用列表中
        invalid_models = [m for m in candidate_models if m not in all_models]
        if invalid_models:
            print(f"[WARN] 以下模型不在可用列表中，可能拼写错误: {invalid_models}")
            print(f"[INFO] 可用模型列表:\n" + "\n".join(f"  - {m}" for m in all_models))
    else:
        # 否则使用原有的过滤逻辑
        candidate_models = [m for m in all_models if not is_embedding_model(m)]
        print(f"[INFO] 过滤掉 {len(all_models) - len(candidate_models)} 个 embedding 模型")
        
        if args.include:
            candidate_models = [m for m in candidate_models if m in args.include]
            print(f"[INFO] 仅测试指定模型: {args.include}")
        if args.exclude:
            candidate_models = [m for m in candidate_models if m not in args.exclude]
            print(f"[INFO] 排除模型: {args.exclude}")

    if not candidate_models:
        print("[ERROR] 过滤后没有可测试的模型。")
        sys.exit(1)

    print(f"[INFO] 将测试以下 {len(candidate_models)} 个模型:")
    for i, m in enumerate(candidate_models, 1):
        print(f"  {i}. {m}")
    print()

    questions = generate_questions(args.questions, seed=args.seed)
    print(f"[INFO] 已生成 {len(questions)} 个测试问题\n")

    per_model_results = []
    for idx, model in enumerate(candidate_models, 1):
        print(f"\n[进度] 模型 {idx}/{len(candidate_models)}")
        res = benchmark_model(args.host, model, questions, args.max_tokens, args.temperature, args.verbose, args.retry, args.delay, args.stream_timeout)
        per_model_results.append(res)

    summary_csv = f"{args.out_prefix}.csv"
    summary_json = f"{args.out_prefix}.json"
    write_csv(summary_csv, per_model_results)
    with open(summary_json, "w", encoding="utf-8") as jf:
        json.dump(per_model_results, jf, ensure_ascii=False, indent=2)

    print(f"[DONE] 汇总写入: {summary_csv} 以及 {summary_json}")
    print("[提示] 可用表格软件查看 CSV，或解析 JSON 进行更深入分析。")


if __name__ == "__main__":
    main()
