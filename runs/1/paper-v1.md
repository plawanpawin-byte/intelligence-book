<!-- job=paper-v1 backend=mlx seconds=121 calls=4 prompt_tokens=6289 gen_tokens=1793 source_chars=10185 source_tokens=2422 note_chars=8625 -->
# "Understanding Attention Mechanisms in Transformers"

The Transformer model introduced attention as a way to improve sequence-to-sequence tasks like machine translation, but did you know that before 2017, most models relied on recurrent neural networks (RNNs) which were inherently sequential and limited information about early tokens from influencing late predictions? As we delve into the world of self-attention mechanisms, you'll learn how this powerful technique relaxes these limitations.

### Big Picture:

Attention mechanisms are essential for achieving state-of-the-art results in many NLP tasks, including language translation, text summarization, and question answering. By enabling the model to weigh the importance of different tokens in a sequence, attention mechanisms allow the Transformer model to focus on the most relevant information and generate more accurate outputs. In this note, we'll explore the inner workings of self-attention mechanisms, including their computation, efficiency, and applications in real-world NLP tasks.

## Attention and the Transformer

### Why attention?

The Transformer model introduced attention as a way to improve the performance of sequence-to-sequence tasks such as machine translation. Before 2017, most models were built using recurrent neural networks (RNNs), which have two well-known weaknesses: computation is inherently sequential and information about early tokens must survive many repeated applications of the model before it can influence a late prediction.

Attention relaxes this by allowing the decoder to look back at every encoder state and decide, for each output step, which input positions are relevant. This approach was first introduced in Bahdanau et al., 2015 as an add-on to recurrent encoder-decoder models.

### Attention as a soft dictionary lookup

A useful mental model for understanding attention is a dictionary (key-value store). In an ordinary dictionary, a query either matches a key exactly or it does not, and we return the corresponding value. Attention relaxes this by comparing the query with every key, producing similarity scores, turning these scores into weights that sum to one, and returning the weighted average of all the values.

For each token in the input, three learned linear maps produce:
- **Query** q_i = x_i W^Q
- **Key** k_i = x_i W^K
- **Value** v_i = x_i W^V

Stacking the rows for all n tokens gives matrices Q, K (each n x d_k) and V (n x d_v).

### Scaled dot-product attention

The Transformer uses the dot product as its similarity function. The complete operation is written:

Attention(Q, K, V) = softmax( Q K^T / sqrt(d_k) ) V

Reading equation (9.1) from the inside out: the product Q K^T is an n x n matrix whose entry (i, j) measures how strongly token i attends to token j.

### Self-attention versus cross-attention

When Q, K, and V are all computed from the same sequence, the operation is called **self-attention**: every token builds a new representation of itself by gathering information from the other tokens in the same sentence.

In contrast, when the queries come from the decoder while the keys and values come from the encoder output, it's called **cross-attention**. This is how a translation model consults the source sentence.

### Multi-head attention

A single attention operation produces one weighted average per token, which limits it to one "kind" of relationship at a time.

Multi-head attention runs h attention operations in parallel, each with its own projection matrices W_i^Q, W_i^K, W_i^V that map into a smaller subspace.

The h outputs are concatenated and passed through a final linear map W^O:

MultiHead(Q, K, V) = Concat(head_1, ..., head_h) W^O
head_i = Attention(Q W_i^Q, K W_i^K, V W_i^V)

### Positional information

Attention by itself is permutation-invariant: if we shuffle the input tokens, each output is shuffled in the same way but otherwise unchanged.

## Efficient Attention Mechanism

### Overview of Self-Attention

Self-attention is a mechanism used in the Transformer model to weigh the importance of different tokens in a sequence. It computes a weighted average of value vectors, with weights given by a softmax over query-key similarities.

> [!definition] Scaled Dot-Product Attention
  The scaled dot-product attention is a type of self-attention that uses a scaling factor (d_k) to prevent the softmax from saturating.
  ==The key idea is to scale the dot product by sqrt(d_k).==

### How Self-Attention Works

Self-attention compares every token with every other token, resulting in a quadratic time and memory complexity. This limits the sequence length to around 512 or 1,024 tokens.

*   **Computing Self-Attention**: The self-attention mechanism computes a weighted average of value vectors, with weights given by a softmax over query-key similarities.
    -   **Query**, **Key**, and **Value** are the three main components of self-attention.
        > [!example] Example
            Query = [q1, q2, ..., qn]
            Key = [k1, k2, ..., kn]
            Value = [v1, v2, ..., vn]
    -   The attention scores are computed using the scaled dot-product attention formula: attention\_scores = softmax(query \* key \* sqrt(d_k) / d_k)
        > [!code]
            attention_scores = softmax(query * key * sqrt(d_k) / d_k)
    -   The weighted sum of value vectors is then computed using the attention scores.

### Efficient Attention Mechanisms

To address the high computational cost of self-attention, several efficient attention mechanisms have been developed, including:

*   **Sparse Patterns**: Using sparse patterns to reduce the number of non-zero elements in the attention matrix.
*   **Low-Rank Approximations**: Approximating the attention matrix as a low-rank matrix to reduce its size.
*   **Memory-Efficient Exact Kernels**: Developing memory-efficient exact kernels for self-attention.

> [!tip] Efficient Attention Mechanism
  When implementing self-attention, consider using an efficient attention mechanism such as sparse patterns or low-rank approximations to reduce computational cost.

## Key Takeaways
- The Transformer model introduced attention as a way to improve sequence-to-sequence tasks, allowing the decoder to look back at every encoder state and decide which input positions are relevant for each output step.
==Attention relaxes the sequential computation problem of RNNs by allowing the decoder to access any part of the input sequence==.
- Attention is analogous to a soft dictionary lookup, where three learned linear maps produce query, key, and value vectors that are then used to compute weighted averages.
==The dot product is used as the similarity function in attention, producing an n x n matrix whose entry (i, j) measures how strongly token i attends to token j==.
- Self-attention versus cross-attention refers to whether the queries come from the decoder or not; self-attention allows every token to build a new representation of itself by gathering information from other tokens.
==Self-attention can be parallelized using multi-head attention, which runs h attention operations in parallel==.
- The Transformer model uses efficient attention mechanisms such as sparse patterns and low-rank approximations to reduce computational cost.

## Review Questions
> [!question] What are the two main weaknesses of RNNs that attention addresses?
> **Answer:** RNNs have two well-known weaknesses: computation is inherently sequential and information about early tokens must survive many repeated applications of the model before it can influence a late prediction. Attention relaxes this by allowing the decoder to access any part of the input sequence.
>
> [!question] How does attention compute weighted averages?
> **Answer:** Attention computes weighted averages using a softmax over query-key similarities, where three learned linear maps produce query, key, and value vectors that are then used to compute the weighted averages.
>
> [!question] What is the difference between self-attention and cross-attention?
> **Answer:** Self-attention allows every token to build a new representation of itself by gathering information from other tokens in the same sentence, whereas cross-attention refers to when the queries come from the decoder while the keys and values come from the encoder output.
>
> [!question] How does multi-head attention parallelize self-attention?
> **Answer:** Multi-head attention runs h attention operations in parallel, each with its own projection matrices W_i^Q, W_i^K, W_i^V that map into a smaller subspace, allowing for parallelization of self-attention.
